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
            active : (pattern, unit) Hashtbl.t }

let depth_bound = 256

let make clauses =
  let by_pred = Hashtbl.create 16 in
  List.iter (fun c ->
      let k = fst c.head in
      let cur = try Hashtbl.find by_pred k with Not_found -> [] in
      Hashtbl.replace by_pred k (cur @ [c]))
    clauses;
  { by_pred; fresh = 0; table = Hashtbl.create 64;
    active = Hashtbl.create 16 }

let is_qvar t = String.length t > 0 && t.[0] = '?'

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
      match Hashtbl.find_opt db.table key with
      | None when Hashtbl.mem db.active key ->
        resolve db g rest subst depth k      (* re-entrant: plain SLD *)
      | found ->
        let answers = match found with
          | Some a -> a | None -> complete db g key in
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
