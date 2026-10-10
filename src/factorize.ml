(* SPDX-License-Identifier: Apache-2.0 *)
exception Factorize_error of string

type env_v = Cst of int | Var of string

type hook_ser = {
  hs_factor : string; hs_args : string list; hs_compl : bool;
  hs_base : string list;
  hs_varats : (string * string) list }

type rec_ = {
  r_name : string; r_weight : float;
  r_deps : string list;
  r_hook : hook_ser option }

type site = {
  s_var : string; s_card : int;
  s_parents : string list;
  s_recs : rec_ list }

type write = {
  w_x : string; w_card : int; w_new : string;
  w_old : string option;
  w_vals : int option list }

type emitted = {
  e_cards : (string * int) list;
  e_sites : site list;
  e_writes : write list;
  e_guards : ((string * int * string) * int list) list;
  e_unknown_vars : (string * string) list;
  e_env : (string, env_v) Hashtbl.t;
  e_maybe_stall : bool }

let fail fmt = Printf.ksprintf (fun s -> raise (Factorize_error s)) fmt

let dedup xs =
  List.rev (List.fold_left (fun acc x ->
      if List.mem x acc then acc else x :: acc) [] xs)

let msk (m : Ground.mset) = List.map fst m
let mmem a (m : Ground.mset) = List.mem_assoc a m

let emit (prog : Ground.program) steps hooks unknowns =
  (* admission: the emission covers 0/1 programs *)
  let check_mset name (m : Ground.mset) =
    List.iter (fun (a, n) ->
        if n > 1 then
          fail "%s: multiplicity %d on '%s' — the emission covers \
                0/1 programs" name n a)
      m in
  check_mset "init" prog.init;
  List.iter (fun (ev : Ground.event) ->
      check_mset ev.ev_name ev.ev_consume;
      check_mset ev.ev_name ev.ev_produce;
      check_mset ev.ev_name ev.ev_persist)
    (Ground.events prog);

  let env : (string, env_v) Hashtbl.t = Hashtbl.create 64 in
  let get a = try Hashtbl.find env a with Not_found -> Cst 0 in
  List.iter (fun (a, _) -> Hashtbl.replace env a (Cst 1)) prog.init;
  let cards = ref [] in
  let mint v card = cards := !cards @ [(v, card)] in
  let unknown_vars =
    List.map (fun a ->
        let v = a ^ "#i" in
        mint v 2; Hashtbl.replace env a (Var v); (a, v))
      (List.sort compare unknowns) in
  let sites = ref [] and writes = ref [] in
  let guards : ((string * int * string) * int list ref) list ref =
    ref [] in
  let maybe_stall = ref false in

  (* deps: None = definitely disabled; Some vars (deduped, order) *)
  let deps (ev : Ground.event) =
    let rec go acc = function
      | [] -> Some (dedup (List.rev acc))
      | a :: rest ->
        (match get a with
         | Cst 0 -> None
         | Cst _ -> go acc rest
         | Var v -> go (v :: acc) rest) in
    go [] (msk ev.ev_consume @ msk ev.ev_persist) in

  let step t stage =
    let clause_cands =
      List.filter_map (fun ev ->
          match deps ev with
          | Some d -> Some (ev, d) | None -> None)
        (List.assoc stage prog.stages) in
    let is_link = (clause_cands = []) in
    let cands =
      if not is_link then clause_cands
      else
        List.filter_map (fun (ev : Ground.event) ->
            if ev.ev_pre <> Some stage then None
            else match deps ev with
              | Some d -> Some (ev, d) | None -> None)
          prog.links in
    if cands = [] then None                     (* done tier *)
    else begin
      if is_link then begin
        let posts = List.sort_uniq compare
            (List.map (fun ((ev : Ground.event), _) ->
                 match ev.ev_post with Some p -> p | None -> "")
                cands) in
        if List.length posts > 1 then
          fail "step %d: branch-dependent stage schedule [%s]" t
            (String.concat ", " posts)
      end;
      let recs = List.map (fun ((ev : Ground.event), d) ->
          let hook = match hooks ev.Ground.ev_name with
            | None -> None
            | Some (h : Ports.hook) ->
              Some { hs_factor = h.hk_factor; hs_args = h.hk_args;
                     hs_compl = h.hk_compl;
                     hs_base = List.sort compare
                         (List.filter (fun a -> get a = Cst 1)
                            h.hk_scope);
                     hs_varats = List.filter_map (fun a ->
                         match get a with
                         | Var v -> Some (a, v) | Cst _ -> None)
                         h.hk_scope } in
          (ev, { r_name = ev.ev_name; r_weight = ev.ev_weight;
                 r_deps = d; r_hook = hook }))
          cands in
      let parents = dedup
          (List.concat_map (fun (_, r) -> r.r_deps) recs
           @ List.concat_map (fun (_, r) -> match r.r_hook with
               | Some h -> List.map snd h.hs_varats
               | None -> [])
             recs) in
      let (ev0, _) = List.hd recs in
      let clean = List.for_all (fun a ->
          get a = Cst 0 || mmem a ev0.Ground.ev_consume)
          (msk ev0.Ground.ev_produce) in
      if List.length recs = 1 && parents = [] && clean then begin
        (* deterministic fold: control vanishes, nothing emitted *)
        List.iter (fun a -> Hashtbl.replace env a (Cst 0))
          (msk ev0.Ground.ev_consume);
        List.iter (fun a -> Hashtbl.replace env a (Cst 1))
          (msk ev0.Ground.ev_produce);
        Some (if is_link then
                (match ev0.Ground.ev_post with
                 | Some p -> p | None -> stage)
              else stage)
      end else begin
        let card = List.length recs in
        let xvar = "X" ^ string_of_int t in
        mint xvar card;
        sites := !sites @
          [{ s_var = xvar; s_card = card; s_parents = parents;
             s_recs = List.map snd recs }];
        let depvars = dedup
            (List.concat_map (fun (_, r) -> r.r_deps) recs) in
        let nd = List.length depvars in
        if nd > 16 then maybe_stall := true
        else begin
          let dv = Array.of_list depvars in
          let idx_of v =
            let rec go i = if dv.(i) = v then i else go (i + 1) in
            go 0 in
          (try
             for mask = 0 to (1 lsl nd) - 1 do
               if not (List.exists (fun (_, r) ->
                   List.for_all (fun d ->
                       (mask lsr idx_of d) land 1 = 1) r.r_deps)
                   recs)
               then begin maybe_stall := true; raise Exit end
             done
           with Exit -> ())
        end;
        let written = dedup
            (List.concat_map (fun ((ev : Ground.event), _) ->
                 msk ev.ev_consume @ msk ev.ev_produce) recs) in
        List.iter (fun a ->
            let old = get a in
            let vals = List.mapi (fun j ((ev : Ground.event), _) ->
                if mmem a ev.ev_produce then begin
                  if not (mmem a ev.ev_consume) then begin
                    (match old with
                     | Cst 1 ->
                       fail "%s: produces '%s' which may already be \
                             present" ev.ev_name a
                     | Var ov ->
                       let key = (xvar, card, ov) in
                       (match List.assoc_opt key !guards with
                        | Some cell ->
                          if not (List.mem j !cell) then
                            cell := !cell @ [j]
                        | None ->
                          guards := !guards @ [(key, ref [j])]);
                       maybe_stall := true
                     | Cst _ -> ())
                  end;
                  Some 1
                end
                else if mmem a ev.ev_consume then Some 0
                else None)
                recs in
            (match old with
             | Cst c ->
               let folded = List.map (function
                   | None -> c | Some v -> v) vals in
               (match folded with
                | f0 :: _ when List.for_all (fun v -> v = f0)
                    folded ->
                  Hashtbl.replace env a (Cst f0)
                | _ ->
                  let nv = Printf.sprintf "%s#%d" a t in
                  mint nv 2;
                  writes := !writes @
                    [{ w_x = xvar; w_card = card; w_new = nv;
                       w_old = None;
                       w_vals = List.map (fun v -> Some v) folded }];
                  Hashtbl.replace env a (Var nv))
             | Var ov ->
               if List.for_all (fun v -> v = None) vals then ()
               else begin
                 let nv = Printf.sprintf "%s#%d" a t in
                 mint nv 2;
                 writes := !writes @
                   [{ w_x = xvar; w_card = card; w_new = nv;
                      w_old = Some ov; w_vals = vals }];
                 Hashtbl.replace env a (Var nv)
               end))
          written;
        Some (if is_link then
                (match ev0.Ground.ev_post with
                 | Some p -> p | None -> stage)
              else stage)
      end
    end in

  let stage = ref (Some prog.init_stage) in
  (try
     for t = 0 to steps - 1 do
       match !stage with
       | None -> raise Exit
       | Some s -> stage := step t s
     done
   with Exit -> ());
  { e_cards = !cards; e_sites = !sites; e_writes = !writes;
    e_guards = List.map (fun (k, cell) -> (k, !cell)) !guards;
    e_unknown_vars = unknown_vars; e_env = env;
    e_maybe_stall = !maybe_stall }

let structure em =
  List.map (fun s -> s.s_parents @ [s.s_var]) em.e_sites
  @ List.map (fun w ->
      [w.w_x; w.w_new]
      @ (match w.w_old with Some o -> [o] | None -> []))
    em.e_writes
  @ List.map (fun ((x, _c, old), _) -> [x; old]) em.e_guards
  @ List.map (fun (_, v) -> [v]) em.e_unknown_vars
