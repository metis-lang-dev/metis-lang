(* SPDX-License-Identifier: Apache-2.0 *)
open Ast

exception Refused of string * string

type result = { lines : string list; costs : string list; mismatches : int }

let refuse code fmt = Printf.ksprintf (fun m -> raise (Refused (code, m))) fmt

module SM = Map.Make (String)

let done_stage = "(done)"

(* "on(wolf,near)" -> ("on", ["wolf"; "near"]) *)
let split_atom s =
  match String.index_opt s '(' with
  | None -> (s, [])
  | Some i ->
    let inner = String.sub s (i + 1) (String.length s - i - 2) in
    (String.sub s 0 i, List.map String.trim (String.split_on_char ',' inner))

let render p args =
  if args = [] then p else Printf.sprintf "%s(%s)" p (String.concat "," args)

let dec r = Printf.sprintf "%.17g" (Rat.to_float r)

(* -- the case's instrument directives (spec/16 §5) ------------------ *)

type mode = Indep | One of string | Lone of string
type belief = { b_pred : string; b_mode : mode; b_port : string }
type quant = Within | At
type query = {
  q_name : string; q_kind : string;
  q_conj : (string * string list) list;     (* `_` matches any argument *)
  q_quant : quant; q_h : int; q_budget : int;
  q_tick : string option }      (* §10.1: h and the step rows count ticks, a tick opening on each
                                   entry into this stage *)
type level_src = From_query of string | From_belief of string
type level = { l_pred : string; l_src : level_src;
               l_at : Rat.t list; l_names : string list }

(* a number as its binary64's shortest round-trip decimal, exactly
   (spec/16 §6.4): what a host's float binding and a case's literal
   both enter as *)
let number what s =
  match float_of_string_opt s with
  | Some f -> (match Rat.of_float f with
      | Some r -> r
      | None -> refuse "port-value" "%s: %s is no number >= 0" what s)
  | None -> refuse "port-value" "%s: %s is no number" what s

let parse dirs =
  let beliefs = ref [] and tbl = ref [] and queries = ref []
  and expects = ref [] and levels = ref [] in
  let bad toks = failwith ("bad instrument directive: " ^ String.concat " " toks) in
  List.iter (fun toks ->
      match toks with
      | ["belief"; p; "by"; port] ->
        beliefs := { b_pred = p; b_mode = Indep; b_port = port } :: !beliefs
      | ["belief"; p; k; v; "by"; port] when k = "one" || k = "lone" ->
        beliefs := { b_pred = p; b_mode = (if k = "one" then One v else Lone v);
                     b_port = port } :: !beliefs
      | "port" :: spec :: vs when vs <> [] && vs <> ["step"] ->
        let (name, args) = split_atom spec in
        let key = if String.contains spec '(' then Some args else None in
        (* one value (the frozen table), or `step v0 v1 …`: a value per
           step of the horizon, row t read at step t (spec/16 §10.1) *)
        let vs = match vs with "step" :: r -> r | [v] -> [v] | _ -> bad toks in
        (* a port bound to anything but a number is a binding that
           computes: the host's function form, spec/16 §10 *)
        List.iter (fun v ->
            if float_of_string_opt v = None then
              refuse "port-function" "port %s bound to %s: a binding that computes is the host's \
                                      function form (spec/16 §10, later); a case binds numbers, a \
                                      table of them, or a table by step" spec v)
          vs;
        tbl := (name, key, Array.of_list (List.map (number ("port " ^ spec)) vs)) :: !tbl
      | "evaluate" :: name :: kind :: rest when kind = "reach" || kind = "risk" ->
        if List.exists (fun q -> q.q_name = name) !queries then
          failwith ("evaluate: the query " ^ name ^ " twice");
        let rec pat acc = function
          | ("within" | "at") as w :: h :: tail ->
            (* the budget, and the world model the query runs over (§5,
               `model`: read by `groups`, the caller's) *)
            let rec opts (b, tk) = function
              | [] -> (b, tk)
              | "budget" :: n :: r -> opts (int_of_string n, tk) r
              | "model" :: _ :: r -> opts (b, tk) r
              | "tick" :: stage :: r -> opts (b, Some stage) r
              | _ -> bad toks in
            let (budget, tick) = opts (500_000, None) tail in
            (List.rev acc, (if w = "within" then Within else At), int_of_string h, budget, tick)
          | "*" :: tail -> pat acc tail
          | a :: tail -> pat (split_atom a :: acc) tail
          | [] -> bad toks in
        let (conj, quant, h, budget, tick) = pat [] rest in
        if conj = [] then bad toks;
        queries := { q_name = name; q_kind = kind; q_conj = conj; q_quant = quant;
                     q_h = h; q_budget = budget; q_tick = tick } :: !queries
      | ["expect"; name; v] -> expects := (name, v) :: !expects
      | "level" :: pred :: "from" :: rest ->
        let (src, rest) = match rest with
          | "belief" :: port :: r -> (From_belief port, r)
          | q :: r -> (From_query q, r)
          | [] -> bad toks in
        let rec split_at acc = function
          | "names" :: names -> (List.rev acc, names)
          | t :: r -> split_at (t :: acc) r
          | [] -> bad toks in
        (match rest with
         | "at" :: r ->
           let (ats, names) = split_at [] r in
           levels := { l_pred = pred; l_src = src;
                       l_at = List.map (number ("level " ^ pred)) ats;
                       l_names = names } :: !levels
         | _ -> bad toks)
      | _ -> bad toks)
    dirs;
  (List.rev !beliefs, List.rev !tbl, List.rev !queries, List.rev !expects, List.rev !levels)

(* -- states ----------------------------------------------------------- *)

type state = { stage : string; counts : int SM.t; undrawn : int list;
               tick : int }      (* the ticks opened since the start (0 without `tick`) *)

let get c a = match SM.find_opt a c with Some n -> n | None -> 0

let key st =
  let b = Buffer.create 64 in
  Buffer.add_string b st.stage; Buffer.add_char b '|';
  SM.iter (fun a n -> Buffer.add_string b a; Buffer.add_char b ':';
            Buffer.add_string b (string_of_int n); Buffer.add_char b ' ') st.counts;
  Buffer.add_char b '|';
  List.iter (fun g -> Buffer.add_string b (string_of_int g); Buffer.add_char b ' ') st.undrawn;
  if st.tick > 0 then (Buffer.add_char b '|'; Buffer.add_string b (string_of_int st.tick));
  Buffer.contents b

let matches (p, args) a =
  let (p', args') = split_atom a in
  p = p' && List.length args = List.length args'
  && List.for_all2 (fun x y -> x = "_" || x = y) args args'

let holds counts conj =
  List.for_all (fun ((p, args) as pat) ->
      if not (List.mem "_" args) then get counts (render p args) > 0
      else SM.exists (fun a n -> n > 0 && matches pat a) counts)
    conj

let falling c n =
  let w = ref 1 in
  for i = 0 to n - 1 do w := !w * max 0 (c - i) done;
  !w

(* the transition count φ (spec 06 §4): falling factorials over the
   consumed counts, count^n over the persisted *)
let phi counts (ev : Ground.event) =
  let w = ref 1 in
  List.iter (fun (a, n) -> w := !w * falling (get counts a) n) ev.Ground.ev_consume;
  List.iter (fun (a, n) -> for _ = 1 to n do w := !w * get counts a done) ev.Ground.ev_persist;
  !w

(* -- the belief groups (spec/16 §2, §3) ------------------------------- *)

type group = {
  g_name : string;
  g_worlds : (string list * Rat.t) list;     (* the atoms present, P > 0 *)
  g_atoms : string list;                      (* its touched atoms *)
  g_stages : string list }                    (* stages whose events touch them *)

let rec product = function
  | [] -> [[]]
  | (f, cs) :: rest ->
    let tails = product rest in
    List.concat_map (fun c -> List.map (fun t -> (f, c) :: t) tails) cs

let run src cat ports prog ~init dirs ~brute =
  let (beliefs, tbl, queries, expects, levels) = parse dirs in
  let sigs = List.filter_map (function DPred (n, ts, _) -> Some (n, ts) | _ -> None)
      src.cdecls in
  let consts ty = match List.assoc_opt ty cat.Catalog.k_types with
    | Some cs -> cs | None -> [] in
  let horn = Ports.horn_db cat in
  List.iter (fun (n, key, _) ->
      match List.assoc_opt n ports.Compile.p_weights, key with
      | None, _ -> refuse "port-unknown" "port %s: not a weight port of the program (%s)" n
                     (String.concat ", " (List.map fst ports.Compile.p_weights))
      | Some formals, Some args when List.length args <> List.length formals ->
        refuse "port-unknown" "port %s: %d arguments, %s takes %d" (render n args)
          (List.length args) n (List.length formals)
      | _ -> ())
    tbl;
  (* row t at step t; past the table's end, its last row (the frozen
     table is the one-row case) *)
  let at_step rows t = rows.(min t (Array.length rows - 1)) in
  let port_rows port args =
    match List.find_opt (fun (n, a, _) -> n = port && a = Some args) tbl with
    | Some (_, _, v) -> v
    | None ->
      (match List.find_opt (fun (n, a, _) -> n = port && a = None) tbl with
       | Some (_, _, v) -> v
       | None -> refuse "port-unbound" "weight port %s is unbound at %s: the case binds it \
                                       (#port %s VALUE, or a value per argument tuple)"
                   port (render port args) port) in
  (* a belief's presence draw reads row 0: the world at the tick *)
  let port_value port args = at_step (port_rows port args) 0 in
  (* the events' weights, prior × the port factor, one per row of the
     port's table (one row: frozen) *)
  let rows = Refsample.canonical_events prog in
  let w_rows = Array.map (fun (r : Refsample.event_row) ->
      let w = number ("rule " ^ r.ev.Ground.ev_name)
          (Printf.sprintf "%.17g" r.ev.Ground.ev_weight) in
      if r.kind = `Link then [| w |]
      else match List.assoc_opt (Ports.base_name r.ev.Ground.ev_name)
                   ports.Compile.p_weight_refs with
        | None -> [| w |]
        | Some wr ->
          let subst = Ports.tag_subst r.ev.Ground.ev_name in
          let args = List.map (fun a -> match List.assoc_opt a subst with
              | Some c -> c | None -> a) wr.Compile.w_args in
          Array.map (fun v ->
              let f = if not wr.Compile.w_compl then v
                else try Rat.sub Rat.one v
                  with Rat.Negative _ -> refuse "port-value" "~%s: %s above 1"
                                           wr.Compile.w_factor (render wr.Compile.w_factor args) in
              Rat.mul w f)
            (port_rows wr.Compile.w_factor args))
      rows in
  let weight i t = at_step w_rows.(i) t in
  let idx kind stage = List.filter (fun i -> rows.(i).Refsample.kind = kind
                                              && rows.(i).Refsample.stage = stage)
      (List.init (Array.length rows) Fun.id) in
  let tiers = Hashtbl.create 8 in
  let tier kind stage =
    match Hashtbl.find_opt tiers (kind, stage) with
    | Some l -> l
    | None -> let l = idx kind stage in Hashtbl.replace tiers (kind, stage) l; l in
  let touched = Hashtbl.create 256 in
  Array.iter (fun (r : Refsample.event_row) ->
      let ev = r.ev in
      List.iter (fun (a, _) -> Hashtbl.replace touched a ())
        (ev.Ground.ev_consume @ ev.Ground.ev_produce @ ev.Ground.ev_persist))
    rows;
  let mentioned a = List.exists (fun q -> List.exists (fun c -> matches c a) q.q_conj) queries in
  (* the beliefs: checked, then their groups *)
  let bpreds = List.map (fun b -> b.b_pred) beliefs in
  List.iter (fun (a, _) ->
      if List.mem (fst (split_atom a)) bpreds then
        refuse "belief-init" "init %s: a belief atom — the instrument draws it from its port, \
                              the case's init must not list it" a)
    init;
  let groups = List.concat_map (fun b ->
      let p = b.b_pred in
      if List.mem p cat.Catalog.k_bwd then
        refuse "belief-bwd" "belief %s: a bwd pred is a guard, eliminated at grounding; every \
                             world shares one ground program, so a belief pred is a resource \
                             pred ($-read it)" p;
      if not (List.mem_assoc p cat.Catalog.k_preds) then
        refuse "belief-port" "belief %s: not a pred of the program" p;
      let formals = match List.assoc_opt b.b_port ports.Compile.p_weights with
        | Some f -> f
        | None -> refuse "belief-port" "belief %s: %s is not a weight port of the program" p b.b_port in
      let pat = match List.assoc_opt b.b_port ports.Compile.p_reads with
        | Some [pat] when pat.ratom.pred = p -> pat
        | _ -> refuse "belief-port" "belief %s: port %s must read exactly one pattern over %s \
                                     (reads {%s(…)})" p b.b_port p p in
      let vars = List.map (function TVar v -> v | TConst c ->
          refuse "belief-port" "belief %s: %s's read pattern has the constant %s; its \
                                arguments are the port's formals" p b.b_port c) pat.ratom.terms in
      if List.sort compare vars <> List.sort compare formals
      || List.length (List.sort_uniq compare vars) <> List.length vars then
        refuse "belief-port" "belief %s: %s's read pattern %s must name each formal of %s(%s) once"
          p b.b_port (atom_str pat.ratom) b.b_port (String.concat ", " formals);
      let types = match List.assoc_opt p sigs with Some ts -> ts | None -> [] in
      let ftype f =
        let rec pos i = function
          | v :: r -> if v = f then i else pos (i + 1) r
          | [] -> 0 in
        List.nth types (pos 0 vars) in
      let atom_of asg = render p (List.map (fun v -> List.assoc v asg) vars) in
      let args_of asg = List.map (fun f -> List.assoc f asg) formals in
      let in_support asg =
        pat.rguards = []
        || List.mem (atom_of asg) (Ports.ground_reads ports b.b_port (args_of asg) horn) in
      let rel a = Hashtbl.mem touched a || mentioned a in
      let stages_of atoms =
        List.sort_uniq compare (List.filter_map (fun (r : Refsample.event_row) ->
            let ev = r.ev in
            if List.exists (fun (a, _) -> List.mem a atoms)
                (ev.Ground.ev_consume @ ev.Ground.ev_produce @ ev.Ground.ev_persist)
            then Some r.stage else None)
            (Array.to_list rows)) in
      let mk name worlds atoms =
        { g_name = name;
          g_worlds = List.filter (fun (_, q) -> not (Rat.is_zero q)) worlds;
          g_atoms = atoms; g_stages = stages_of atoms } in
      match b.b_mode with
      | Indep ->
        List.filter_map (fun asg ->
            if not (in_support asg) then None
            else
              let a = atom_of asg in
              let q = port_value b.b_port (args_of asg) in
              if Rat.compare q Rat.one > 0 then
                refuse "belief-sum" "belief %s: %s = %s (%s) is above 1" p
                  (render b.b_port (args_of asg)) (Rat.to_string q) (dec q);
              if rel a then Some (mk a [([a], q); ([], Rat.sub Rat.one q)] [a]) else None)
          (product (List.map (fun f -> (f, consts (ftype f))) formals))
      | One v | Lone v ->
        if not (List.mem v formals) then
          refuse "belief-port" "belief %s: %s is not a formal of %s(%s)" p v b.b_port
            (String.concat ", " formals);
        let others = List.filter (fun f -> f <> v) formals in
        List.filter_map (fun kasg ->
            let members = List.filter in_support
                (List.map (fun c -> (v, c) :: kasg) (consts (ftype v))) in
            let ps = List.map (fun asg -> (atom_of asg, port_value b.b_port (args_of asg))) members in
            let total = List.fold_left (fun acc (_, q) -> Rat.add acc q) Rat.zero ps in
            let gname = render p (List.map (fun x -> if x = v then "_" else List.assoc x kasg) vars) in
            (match b.b_mode with
             | One _ when Rat.compare total Rat.one <> 0 ->
               refuse "belief-sum" "belief %s one %s: the group %s sums to %s (%s), not 1"
                 p v gname (Rat.to_string total) (dec total)
             | Lone _ when Rat.compare total Rat.one > 0 ->
               refuse "belief-sum" "belief %s lone %s: the group %s sums to %s (%s), above 1"
                 p v gname (Rat.to_string total) (dec total)
             | _ -> ());
            let live = List.filter (fun (a, _) -> rel a) ps in
            if live = [] then None                      (* R1: weakening *)
            else
              let rest = Rat.sub Rat.one
                  (List.fold_left (fun acc (_, q) -> Rat.add acc q) Rat.zero live) in
              Some (mk gname (List.map (fun (a, q) -> ([a], q)) live @ [([], rest)])
                      (List.map fst live)))
          (product (List.map (fun f -> (f, consts (ftype f))) others)))
      beliefs in
  let groups = Array.of_list groups in
  let ng = Array.length groups in
  let worlds = Array.fold_left (fun acc g -> acc * List.length g.g_worlds) 1 groups in
  (* the choice at a state: spec 06 §4's tiers, exactly *)
  let choice st t =
    if st.stage = done_stage then [(None, Rat.one)]
    else
      let weigh kind =
        List.filter_map (fun i ->
            let n = phi st.counts rows.(i).Refsample.ev in
            if n = 0 then None
            else let w = Rat.mul (weight i t) (Rat.of_int n) in
              if Rat.is_zero w then None else Some (i, w))
          (tier kind st.stage) in
      let ws = match weigh `Clause with [] -> weigh `Link | ws -> ws in
      match ws with
      | [] -> [(None, Rat.one)]
      | _ ->
        let tot = List.fold_left (fun acc (_, w) -> Rat.add acc w) Rat.zero ws in
        List.map (fun (i, w) -> (Some i, Rat.div w tot)) ws in
  let apply tk st = function
    | None -> { st with stage = done_stage }
    | Some i ->
      let r = rows.(i) in
      let ev = r.Refsample.ev in
      let c = List.fold_left (fun c (a, n) ->
          let m = get c a - n in if m > 0 then SM.add a m c else SM.remove a c)
          st.counts ev.Ground.ev_consume in
      let c = List.fold_left (fun c (a, n) -> SM.add a (get c a + n) c) c ev.Ground.ev_produce in
      let stage = match r.Refsample.kind, ev.Ground.ev_post with
        | `Link, Some p -> p | _ -> st.stage in
      (* a link into the tick's stage opens the next tick *)
      let tick = match r.Refsample.kind, tk with
        | `Link, Some s when s = stage -> st.tick + 1 | _ -> st.tick in
      { st with counts = c; stage; tick }
  in
  (* R2: a group is drawn where its presence could first matter *)
  let rec settle must st m =
    match List.find_opt (fun g -> must groups.(g) st) st.undrawn with
    | None -> [(st, m)]
    | Some gid ->
      let undrawn = List.filter (( <> ) gid) st.undrawn in
      List.concat_map (fun (atoms, q) ->
          let counts = List.fold_left (fun c a -> SM.add a (get c a + 1) c) st.counts atoms in
          settle must { st with counts; undrawn } (Rat.mul m q))
        groups.(gid).g_worlds in
  let st0 = { stage = prog.Ground.init_stage;
              counts = List.fold_left (fun c (a, n) -> if n > 0 then SM.add a n c else c)
                  SM.empty init;
              undrawn = List.init ng Fun.id; tick = 0 } in
  let maxbits = ref 0 in
  let note m = let b = Rat.den_bits m in if b > !maxbits then maxbits := b in
  let instrument q =
    let qg g = List.exists (fun a -> List.exists (fun c -> matches c a) q.q_conj) g.g_atoms in
    let must g st = qg g || List.mem st.stage g.g_stages in
    let hit = ref Rat.zero and cut = ref Rat.zero and retained = ref 0 in
    (* by tick (§10.1): a state that has opened tick h is finished, and so
       is one at DONE; at: the final slice is what finishes *)
    let finished st = match q.q_tick with
      | Some _ -> st.tick >= q.q_h || st.stage = done_stage | None -> false in
    let final = Hashtbl.create 64 in
    let put tbl st m =
      let k = key st in
      match Hashtbl.find_opt tbl k with
      | Some (s, m0) -> Hashtbl.replace tbl k (s, Rat.add m0 m)
      | None -> Hashtbl.replace tbl k (st, m) in
    let admit tbl (st, m) =
      note m;
      if q.q_quant = Within && holds st.counts q.q_conj then hit := Rat.add !hit m
      else if q.q_quant = Within && (st.stage = done_stage || finished st) then ()   (* a miss *)
      else if finished st then put final st m
      else put tbl st m in
    let cur = ref (Hashtbl.create 64) in
    List.iter (admit !cur) (settle must st0 Rat.one);
    retained := Hashtbl.length !cur;
    let t = ref 0 in
    let row st = match q.q_tick with Some _ -> st.tick | None -> !t - 1 in
    while (q.q_tick <> None || !t < q.q_h) && Hashtbl.length !cur > 0 do
      incr t;
      let out = Hashtbl.create 64 in
      let states = List.sort (fun (a, _) (b, _) -> compare a b)
          (Hashtbl.fold (fun k v acc -> (k, v) :: acc) !cur []) in
      List.iter (fun (_, (st, m)) ->
          if !retained + Hashtbl.length out >= q.q_budget then cut := Rat.add !cut m
          else
            List.iter (fun (e, p) ->
                List.iter (admit out) (settle must (apply q.q_tick st e) (Rat.mul m p)))
              (choice st (row st)))
        states;
      retained := !retained + Hashtbl.length out;
      cur := out
    done;
    let lo = match q.q_quant with
      | Within -> !hit
      | At -> Hashtbl.fold (fun _ (st, m) acc ->
          if holds st.counts q.q_conj then Rat.add acc m else acc)
          (if q.q_tick = None then !cur else final) Rat.zero in
    (lo, Rat.add lo !cut, !cut, !retained) in
  let referee q =
    let hit = ref Rat.zero and paths = ref 0 in
    let over st t = st.stage = done_stage
                    || (match q.q_tick with Some _ -> st.tick >= q.q_h | None -> t = q.q_h) in
    let row st t = match q.q_tick with Some _ -> st.tick | None -> t in
    let rec dfs st m t =
      let next () = List.iter (fun (e, p) -> dfs (apply q.q_tick st e) (Rat.mul m p) (t + 1))
          (choice st (row st t)) in
      match q.q_quant with
      | Within ->
        if holds st.counts q.q_conj then (hit := Rat.add !hit m; incr paths)
        else if over st t then incr paths
        else next ()
      | At ->
        if over st t then begin
          incr paths;
          if holds st.counts q.q_conj then hit := Rat.add !hit m
        end
        else next () in
    List.iter (fun (st, m) -> dfs st m 0) (settle (fun _ _ -> true) st0 Rat.one);
    (!hit, !paths) in
  (* the listing *)
  let notes = ref [] in
  List.iter (fun (e : Catalog.entry) ->
      let reads = match e.e_payload with
        | Catalog.PSchema s -> s.cs_consume @ s.cs_persist @ s.cs_guards
        | Catalog.PLink l -> l.ls_consume @ l.ls_persist @ l.ls_guards
        | Catalog.PHorn _ -> [] in
      List.iter (fun p ->
          let rule = match String.rindex_opt e.e_name '/' with
            | Some i -> String.sub e.e_name (i + 1) (String.length e.e_name - i - 1)
            | None -> e.e_name in
          let line = Printf.sprintf "N belief-read %s %s" rule p in
          if List.exists (fun (q, _) -> q = p) reads && not (List.mem line !notes) then
            notes := line :: !notes)
        bpreds)
    cat.Catalog.k_entries;
  (* a port read by step (spec/16 §10.1): its rows, and §8's
     multilinearity gone for it *)
  List.iter (fun (n, _, r) ->
      let k = List.fold_left (fun acc (m, _, r') -> if m = n then max acc (Array.length r') else acc)
          0 tbl in
      let line = Printf.sprintf "N step-table %s rows %d" n k in
      if Array.length r > 1 && not (List.mem line !notes) then notes := line :: !notes)
    tbl;
  let results = ref [] and costs = ref [] and mism = ref 0 in
  let vlines = List.map (fun q ->
      let pat = String.concat " * " (List.map (fun (p, a) -> render p a) q.q_conj) in
      let head = Printf.sprintf "V %s %s %s %s %d%s" q.q_name q.q_kind pat
          (if q.q_quant = Within then "within" else "at") q.q_h
          (match q.q_tick with Some s -> " tick " ^ s | None -> "") in
      maxbits := 0;
      let t0 = Sys.time () in
      let (lo, hi, cut, line) =
        if brute then
          let (v, paths) = referee q in
          (v, v, Rat.zero, Printf.sprintf "%s = %s ~ %s worlds %d paths %d" head
             (Rat.to_string v) (dec v) worlds paths)
        else
          let (lo, hi, cut, n) = instrument q in
          if Rat.is_zero cut then
            (lo, hi, cut, Printf.sprintf "%s = %s ~ %s worlds %d states %d" head
               (Rat.to_string lo) (dec lo) worlds n)
          else
            (lo, hi, cut, Printf.sprintf "%s in [%s, %s] ~ [%s, %s] cut %s worlds %d states %d"
               head (Rat.to_string lo) (Rat.to_string hi) (dec lo) (dec hi) (dec cut) worlds n) in
      let ms = (Sys.time () -. t0) *. 1000.0 in
      costs := Printf.sprintf "C %s h %d groups %d worlds %d bits %d digits %d ms %.1f"
          q.q_name q.q_h ng worlds !maxbits (Rat.den_digits hi) ms :: !costs;
      results := (q.q_name, (lo, hi, cut)) :: !results;
      line)
      queries in
  (* expectations *)
  let xlines = List.filter_map (fun (name, v) ->
      match List.assoc_opt name !results with
      | None -> incr mism; Some (Printf.sprintf "X %s: no such query" name)
      | Some (lo, hi, _) ->
        let ok =
          if String.contains v '/' then Rat.compare lo hi = 0 && Rat.to_string lo = v
          else match float_of_string_opt v with
            | Some f -> Rat.to_float lo <= f && f <= Rat.to_float hi
            | None -> false in
        if ok then None
        else (incr mism;
              Some (Printf.sprintf "X %s expected %s got %s" name v
                      (if Rat.compare lo hi = 0 then dec lo
                       else Printf.sprintf "[%s, %s]" (dec lo) (dec hi)))))
      expects in
  (* level ports (§4) *)
  let level_of l r =
    List.nth l.l_names (List.length (List.filter (fun t -> Rat.compare t r <= 0) l.l_at)) in
  let llines = List.concat_map (fun l ->
      let types = match List.assoc_opt l.l_pred sigs with
        | Some ts -> ts
        | None -> refuse "level-type" "level %s: not a pred of the program" l.l_pred in
      (match types with
       | t :: _ when consts t = l.l_names -> ()
       | _ -> refuse "level-type" "level %s: its first argument's type must have the \
                                   constants %s, in order" l.l_pred (String.concat " " l.l_names));
      if List.length l.l_names <> List.length l.l_at + 1 then
        refuse "level-type" "level %s: %d names for %d thresholds" l.l_pred
          (List.length l.l_names) (List.length l.l_at);
      let rec incr_ok = function
        | a :: (b :: _ as r) -> Rat.compare a b < 0 && incr_ok r
        | _ -> true in
      if not (incr_ok l.l_at) then refuse "level-type" "level %s: thresholds not increasing" l.l_pred;
      match l.l_src with
      | From_query qn ->
        (match List.assoc_opt qn !results with
         | None -> refuse "level-type" "level %s: no query %s" l.l_pred qn
         | Some (lo, hi, _) ->
           let a = level_of l lo and b = level_of l hi in
           [if a = b then Printf.sprintf "L %s" (render l.l_pred [a])
            else Printf.sprintf "L %s cut" (render l.l_pred [a ^ ".." ^ b])])
      | From_belief port ->
        (match List.find_opt (fun b -> b.b_port = port) beliefs with
         | None -> refuse "level-type" "level %s: no belief by %s" l.l_pred port
         | Some _ ->
           let formals = List.assoc port ports.Compile.p_weights in
           if List.length types <> 1 + List.length formals then
             refuse "level-type" "level %s: %d arguments, the level and %s's %d formals"
               l.l_pred (List.length types) port (List.length formals);
           let pat = List.hd (List.assoc port ports.Compile.p_reads) in
           let vars = List.map (function TVar v -> v | TConst c -> c) pat.ratom.terms in
           List.concat_map (fun g ->
               List.filter_map (fun (atoms, q) ->
                   match atoms with
                   | [a] when fst (split_atom a) = pat.ratom.pred ->
                     let vals = snd (split_atom a) in
                     let asg = List.combine vars vals in
                     let args = List.map (fun f -> List.assoc f asg) formals in
                     Some (Printf.sprintf "L %s" (render l.l_pred (level_of l q :: args)))
                   | _ -> None)
                 g.g_worlds)
             (List.filter (fun g -> List.exists (fun a -> fst (split_atom a) = pat.ratom.pred)
                              g.g_atoms) (Array.to_list groups))))
      levels in
  { lines = List.rev !notes @ vlines @ llines @ xlines;
    costs = List.rev !costs; mismatches = !mism }

(* -- the case and manifest YAML (spec/16 §5) ---------------------------- *)

let squash a =
  let b = Buffer.create (String.length a) and depth = ref 0 in
  String.iter (fun c ->
      if c = '(' then incr depth else if c = ')' then decr depth;
      if not (!depth > 0 && (c = ' ' || c = '\t')) then Buffer.add_char b c) a;
  Buffer.contents b

let case_of_yaml path =
  let open Iface in
  let bad fmt = Printf.ksprintf (fun m -> raise (Yaml_error (path ^ ": " ^ m))) fmt in
  let str what = function S s -> s | _ -> bad "%s: expected a scalar" what in
  let lst what = function L l -> l | _ -> bad "%s: expected a flow list" what in
  let map what = function M m -> m | _ -> bad "%s: expected a map" what in
  let case = read_yaml_block path in
  List.iter (fun (k, _) ->
      if not (List.mem k ["case"; "manifest"; "init"; "ports"; "evaluate"; "expect"]) then
        bad "unknown key %s (case, manifest, init, ports, evaluate, expect)" k)
    case;
  let dir = Filename.dirname path in
  let mpath = match List.assoc_opt "manifest" case with
    | Some v -> Filename.concat dir (str "manifest" v)
    | None ->
      if Filename.basename dir = "cases" then Filename.concat (Filename.dirname dir) "domain.yaml"
      else Filename.concat dir "domain.yaml" in
  let man = read_yaml_block mpath in
  let program = match List.assoc_opt "program" man with
    | Some v -> Filename.concat (Filename.dirname mpath) (str "program" v)
    | None -> bad "%s: no program" mpath in
  let init = match List.assoc_opt "init" case with
    | None -> []
    | Some v ->
      List.map (fun x ->
          let t = squash (str "init" x) in
          match String.rindex_opt t ' ' with
          | Some i when int_of_string_opt (String.sub t (i + 1) (String.length t - i - 1)) <> None ->
            (String.sub t 0 i, int_of_string (String.sub t (i + 1) (String.length t - i - 1)))
          | _ -> (t, 1))
        (lst "init" v) in
  let beliefs = match List.assoc_opt "beliefs" man with
    | None -> []
    | Some v ->
      List.map (fun (pred, f) ->
          let f = map ("beliefs " ^ pred) f in
          let port = match List.assoc_opt "port" f with
            | Some p -> str "port" p | None -> bad "beliefs %s: no port" pred in
          match List.assoc_opt "one" f, List.assoc_opt "lone" f with
          | Some v, None -> ["belief"; pred; "one"; str "one" v; "by"; port]
          | None, Some v -> ["belief"; pred; "lone"; str "lone" v; "by"; port]
          | None, None -> ["belief"; pred; "by"; port]
          | _ -> bad "beliefs %s: one or lone, not both" pred)
        (map "beliefs" v) in
  let queries src = match List.assoc_opt "evaluate" src with
    | None -> []
    | Some v ->
      List.map (fun (name, f) ->
          let f = map ("evaluate " ^ name) f in
          let (kind, pat) = match List.assoc_opt "reach" f, List.assoc_opt "risk" f with
            | Some p, None -> ("reach", str "reach" p)
            | None, Some p -> ("risk", str "risk" p)
            | _ -> bad "evaluate %s: one of reach, risk" name in
          let (q, h) = match List.assoc_opt "within" f, List.assoc_opt "at" f with
            | Some h, None -> ("within", str "within" h)
            | None, Some h -> ("at", str "at" h)
            | _ -> bad "evaluate %s: one of within, at" name in
          let budget = match List.assoc_opt "budget" f with
            | Some b -> ["budget"; str "budget" b] | None -> [] in
          let budget = budget @ (match List.assoc_opt "model" f with
              | Some m -> ["model"; str "model" m] | None -> [])
                       @ (match List.assoc_opt "tick" f with
                           | Some t -> ["tick"; str "tick" t] | None -> []) in
          List.iter (fun (k, _) ->
              if not (List.mem k ["reach"; "risk"; "within"; "at"; "budget"; "model"; "tick"]) then
                bad "evaluate %s: unknown key %s (reach|risk, within|at, budget, model, tick)" name k)
            f;
          let toks = List.filter (( <> ) "")
              (String.split_on_char ' ' (squash pat)) in
          ["evaluate"; name; kind] @ toks @ [q; h] @ budget)
        (map "evaluate" v) in
  let levels = match List.assoc_opt "levels" man with
    | None -> []
    | Some v ->
      List.map (fun (pred, f) ->
          let f = map ("levels " ^ pred) f in
          let src = match List.assoc_opt "from" f with
            | Some (M [("evaluate", q)]) -> [str "from" q]
            | Some (M [("belief", p)]) -> ["belief"; str "from" p]
            | _ -> bad "levels %s: from: {evaluate: Q} or {belief: PORT}" pred in
          let get k = match List.assoc_opt k f with
            | Some l -> List.map (str k) (lst k l) | None -> bad "levels %s: no %s" pred k in
          ["level"; pred; "from"] @ src @ ["at"] @ get "at" @ ["names"] @ get "names")
        (map "levels" v) in
  let ports = match List.assoc_opt "ports" case with
    | None -> []
    | Some v ->
      List.concat_map (fun (port, b) ->
          match b with
          | S x -> [["port"; port; x]]
          | M [("step", L rows)] ->
            (* a table by step (spec/16 §10.1): a number per row, or the
               same atom table in every row *)
            (match rows with
             | [] -> bad "ports %s: step: an empty table" port
             | S _ :: _ ->
               [["port"; port; "step"] @ List.map (str ("ports " ^ port ^ " step")) rows]
             | M first :: _ ->
               let atoms = List.map fst first in
               let tbls = List.map (fun r -> match r with
                   | M t when List.sort compare (List.map fst t) = List.sort compare atoms -> t
                   | _ -> bad "ports %s: step: every row the same atoms as the first (%s)" port
                            (String.concat ", " atoms)) rows in
               List.map (fun atom ->
                   let a = squash atom in
                   if fst (split_atom a) <> port then
                     bad "ports %s: the entry %s is not an argument tuple of %s" port atom port;
                   ["port"; a; "step"]
                   @ List.map (fun t -> str ("ports " ^ atom) (List.assoc atom t)) tbls)
                 atoms
             | L _ :: _ -> bad "ports %s: step: a row is a number or an atom table" port)
          | M tbl ->
            List.map (fun (atom, x) ->
                let a = squash atom in
                if fst (split_atom a) <> port then
                  bad "ports %s: the entry %s is not an argument tuple of %s" port atom port;
                ["port"; a; str ("ports " ^ atom) x])
              tbl
          | L _ -> refuse "port-function" "port %s bound to a list: a binding that computes is \
                                           the host's function form (spec/16 §10, later); a \
                                           case binds numbers or a table of them" port)
        (map "ports" v) in
  let expects = match List.assoc_opt "expect" case with
    | None -> []
    | Some v -> List.map (fun (n, x) -> ["expect"; n; str "expect" x]) (map "expect" v) in
  (Filename.dirname mpath, str "program" (List.assoc "program" man), init,
   beliefs @ ports @ queries man @ queries case @ expects @ levels)

(* -- the queries' world models (spec/16 §3, §5 `model`) ---------------- *)

let model_of d =
  let rec f = function "model" :: p :: _ -> Some p | _ :: r -> f r | [] -> None in
  match d with "evaluate" :: _ -> f d | _ -> None

let groups dirs ~program =
  List.iter (fun d ->
      match model_of d with
      | None -> ()
      | Some m ->
        (* inside the package: relative, and never above its root *)
        let depth = List.fold_left (fun acc c ->
            if acc < 0 then acc
            else match c with "" | "." -> acc | ".." -> acc - 1 | _ -> acc + 1)
            0 (String.split_on_char '/' m) in
        if not (Filename.is_relative m) || depth < 0 then
          refuse "model-path" "evaluate %s: model %s is outside the package" (List.nth d 1) m)
    dirs;
  let qkey = List.filter_map (fun d -> match d with
      | "evaluate" :: name :: _ ->
        Some (name, match model_of d with Some m -> m | None -> program)
      | _ -> None) dirs in
  let keys = match List.sort_uniq compare (List.map snd qkey) with [] -> [program] | ks -> ks in
  List.mapi (fun i key ->
      let first = i = 0 in
      let mine q = match List.assoc_opt q qkey with Some k -> k = key | None -> first in
      (key, List.filter (fun d -> match d with
           | ("belief" | "port") :: _ -> true
           | "evaluate" :: name :: _ -> mine name
           | "expect" :: name :: _ -> mine name
           | "level" :: _ :: "from" :: "belief" :: _ -> first
           | "level" :: _ :: "from" :: q :: _ -> mine q
           | _ -> first) dirs))
    keys
