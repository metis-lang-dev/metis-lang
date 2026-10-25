(* SPDX-License-Identifier: Apache-2.0 *)
type pattern = string * string list

type clause = { head : pattern; body : pattern list;
                vars : string list }

(* VARIANT TABLING (mirrors metispy kernel/horn.py): the distinct
   answers of each call pattern — constants kept, variables abstracted
   by first occurrence (?#0, ?#1, ...) — are computed once, in SLD
   order, and replayed. derivable is existence and solutions dedups
   first-wins, so per-call first-found dedup preserves the observable
   answers and their order; recomputation of shared subgoals (plus/
   mult over unary nats: ~n^6) disappears. A call re-entering a
   variant still being tabled falls back to plain SLD; a tabled call
   gets its own depth budget (per call, not per whole derivation). *)
type db = { by_pred : (string, clause list) Hashtbl.t;
            mutable fresh : int;
            table : (pattern, string list list) Hashtbl.t;
            active : (pattern, unit) Hashtbl.t;
            facts : (string, fact_index) Hashtbl.t }

(* BY-POSITION FACT INDEX (eval-perf step 2): a predicate whose
   clauses are all ground facts is answered from an index, untabled,
   instead of a scan of every clause per new call (the cells^3 of a
   static adjacency table). Answers are exactly the scan's: the
   candidates of a bound position are a superset of the matches, kept
   in clause order, and each is unified as the scan would. *)
and fact_index = { fx_all : clause list;
                   fx_ground : (string list, unit) Hashtbl.t;
                   fx_pos : (int * string, clause list) Hashtbl.t }

let depth_bound = 256

let is_qvar t = String.length t > 0 && t.[0] = '?'

let ground_fact c =
  c.body = [] && c.vars = [] && not (List.exists is_qvar (snd c.head))

let index_facts cls =
  let fx = { fx_all = cls; fx_ground = Hashtbl.create 64;
             fx_pos = Hashtbl.create 64 } in
  (* newest-first, reversed once: clause order kept per bucket *)
  List.iter (fun c ->
      Hashtbl.replace fx.fx_ground (snd c.head) ();
      List.iteri (fun i a ->
          let k = (i, a) in
          Hashtbl.replace fx.fx_pos k
            (c :: (try Hashtbl.find fx.fx_pos k with Not_found -> [])))
        (snd c.head))
    cls;
  Hashtbl.filter_map_inplace (fun _ l -> Some (List.rev l)) fx.fx_pos;
  fx

let make clauses =
  let by_pred = Hashtbl.create 16 in
  List.iter (fun c ->
      let k = fst c.head in
      Hashtbl.replace by_pred k
        (c :: (try Hashtbl.find by_pred k with Not_found -> [])))
    clauses;
  Hashtbl.filter_map_inplace (fun _ l -> Some (List.rev l)) by_pred;
  let facts = Hashtbl.create 16 in
  Hashtbl.iter (fun k cls ->
      if List.for_all ground_fact cls then
        Hashtbl.replace facts k (index_facts cls))
    by_pred;
  { by_pred; fresh = 0; table = Hashtbl.create 64;
    active = Hashtbl.create 16; facts }

let rename db cl =
  if cl.vars = [] then cl
  else begin
    db.fresh <- db.fresh + 1;
    let m = List.map (fun v ->
        (v, Printf.sprintf "?%s@%d" v db.fresh)) cl.vars in
    let r (p, args) =
      (p, List.map (fun a ->
           match List.assoc_opt a m with Some x -> x | None -> a)
          args) in
    { head = r cl.head; body = List.map r cl.body; vars = [] }
  end

let rec walk t subst =
  if is_qvar t then
    match List.assoc_opt t subst with
    | Some t' -> walk t' subst
    | None -> t
  else t

let unify (pa, aa) (pb, ab) subst =
  if pa <> pb || List.length aa <> List.length ab then None
  else
    let rec go s = function
      | [], [] -> Some s
      | x :: xs, y :: ys ->
        let x = walk x s and y = walk y s in
        if x = y then go s (xs, ys)
        else if is_qvar x then go ((x, y) :: s) (xs, ys)
        else if is_qvar y then go ((y, x) :: s) (xs, ys)
        else None
      | _ -> None in
    go subst (aa, ab)

let variant args =
  let m = ref [] in
  List.map (fun a ->
      if is_qvar a then
        match List.assoc_opt a !m with
        | Some c -> c
        | None ->
          let c = Printf.sprintf "?#%d" (List.length !m) in
          m := (a, c) :: !m; c
      else a) args

(* depth-first SLD; calls k on every solution substitution, in
   enumeration order; k returns true to STOP (early exit) *)
let rec solve db goals subst depth k =
  match goals with
  | [] -> k subst
  | g0 :: rest ->
    if depth <= 0 then false
    else begin
      let g = (fst g0, List.map (fun a -> walk a subst) (snd g0)) in
      let key = (fst g, variant (snd g)) in
      let answers = match Hashtbl.find_opt db.facts (fst g) with
        | Some fx -> Some (fact_answers fx g (snd key))
        | None ->
          match Hashtbl.find_opt db.table key with
          | None when Hashtbl.mem db.active key -> None
          | Some a -> Some a
          | None -> Some (complete db g key) in
      match answers with
      | None -> resolve db g rest subst depth k  (* re-entrant: plain SLD *)
      | Some answers ->
        List.exists (fun ans ->
            db.fresh <- db.fresh + 1;
            let inst = List.map (fun a ->
                if is_qvar a then Printf.sprintf "%s@%d" a db.fresh
                else a) ans in
            match unify (fst g, inst) g subst with
            | None -> false
            | Some s2 -> solve db rest s2 (depth - 1) k)
          answers
    end

(* plain SLD step on goal g: one branch per matching clause *)
and resolve db g rest subst depth k =
  let cls = try Hashtbl.find db.by_pred (fst g) with Not_found -> [] in
  List.exists (fun cl ->
      let r = rename db cl in
      match unify r.head g subst with
      | None -> false
      | Some s2 -> solve db (r.body @ rest) s2 (depth - 1) k)
    cls

(* complete's answers for a fact-only predicate, from its index: a
   ground call is a lookup; otherwise the smallest bucket of a bound
   position (all facts when none is bound), unified in clause order *)
and fact_answers fx g args =
  if not (List.exists is_qvar args) then
    (if Hashtbl.mem fx.fx_ground args then [args] else [])
  else begin
    let best = ref None in
    List.iteri (fun i a ->
        if not (is_qvar a) then begin
          let b = try Hashtbl.find fx.fx_pos (i, a) with Not_found -> [] in
          let n = List.length b in
          match !best with
          | Some (m, _) when m <= n -> ()
          | _ -> best := Some (n, b)
        end)
      args;
    let cands = match !best with Some (_, b) -> b | None -> fx.fx_all in
    let answers = ref [] and seen = Hashtbl.create 8 in
    List.iter (fun cl ->
        match unify cl.head g [] with
        | None -> ()
        | Some s ->
          let ans = variant (List.map (fun a -> walk a s) (snd g)) in
          if not (Hashtbl.mem seen ans) then begin
            Hashtbl.add seen ans ();
            answers := ans :: !answers
          end)
      cands;
    List.rev !answers
  end

(* all distinct answers (g's args instantiated, variables
   canonicalized) in SLD order — the first only, for a ground g *)
and complete db g key =
  Hashtbl.replace db.active key ();
  let ground = List.for_all (fun a -> not (is_qvar a)) (snd key) in
  let answers = ref [] and seen = Hashtbl.create 8 in
  (try
     ignore (resolve db g [] [] depth_bound (fun s3 ->
         let ans = variant (List.map (fun a -> walk a s3) (snd g)) in
         if not (Hashtbl.mem seen ans) then begin
           Hashtbl.add seen ans ();
           answers := ans :: !answers
         end;
         ground && !answers <> []))
   with e -> Hashtbl.remove db.active key; raise e);
  Hashtbl.remove db.active key;
  let a = List.rev !answers in
  Hashtbl.replace db.table key a;
  a

let derivable db goal =
  solve db [goal] [] depth_bound (fun _ -> true)

let solutions db goals =
  let vs = List.sort_uniq compare
      (List.concat_map (fun (_, args) -> List.filter is_qvar args)
         goals) in
  let seen = Hashtbl.create 16 in
  let out = ref [] in
  ignore (solve db goals [] depth_bound (fun s ->
      let key = List.map (fun v -> walk v s) vs in
      if List.exists is_qvar key then
        (* a quantified fact var answered the query without being
           pinned: enumerable only through its type, which the Horn
           world does not carry *)
        failwith "non-ground Horn solution: a fact variable is left \
                  unbound — guard it with a predicate that enumerates it";
      if not (Hashtbl.mem seen key) then begin
        Hashtbl.add seen key ();
        out := List.map2 (fun v c ->
            (String.sub v 1 (String.length v - 1), c)) vs key
               :: !out
      end;
      false));
  List.rev !out
