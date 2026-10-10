(* SPDX-License-Identifier: Apache-2.0 *)
exception Bpn_error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Bpn_error s)) fmt

let boxes (em : Factorize.emitted) =
  List.map (fun (s : Factorize.site) ->
      ("site " ^ s.s_var, s.s_var, s.s_parents))
    em.e_sites
  @ List.map (fun (w : Factorize.write) ->
      ("write " ^ w.w_new, w.w_new,
       w.w_x :: (match w.w_old with Some o -> [o] | None -> [])))
    em.e_writes
  @ List.map (fun (a, v) -> ignore a; ("prior " ^ v, v, []))
      em.e_unknown_vars
  @ List.mapi (fun k ((x, _c, old), _) ->
      (Printf.sprintf "guard !g%d" k, Printf.sprintf "!g%d" k,
       [x; old]))
    em.e_guards

let check em =
  let bs = boxes em in
  List.iter (fun (label, concl, prem) ->
      if List.mem concl prem then
        fail "%s: its own premise (box rule requires X not in Yi)"
          label)
    bs;
  let producer = Hashtbl.create 64 in
  List.iter (fun (label, concl, _) ->
      if Hashtbl.mem producer concl then
        fail "'%s' concluded twice: %s and %s — the emission is not \
              SSA" concl (Hashtbl.find producer concl) label;
      Hashtbl.replace producer concl label)
    bs;
  List.iter (fun (label, _, prem) ->
      List.iter (fun p ->
          if not (Hashtbl.mem producer p) then
            fail "%s: premise '%s' is the conclusion of no box"
              label p)
        prem)
    bs;
  List.iter (fun (v, _) ->
      if not (Hashtbl.mem producer v) then
        fail "variable '%s' has a cardinality but no producing box" v)
    em.e_cards;
  (* Lemma 3.1: polarized orientation is a DAG (Kahn) *)
  let out = Hashtbl.create 64 and indeg = Hashtbl.create 64 in
  List.iter (fun (_, concl, _) -> Hashtbl.replace indeg concl 0) bs;
  List.iter (fun (_, concl, prem) ->
      List.iter (fun p ->
          let cur = try Hashtbl.find out p with Not_found -> [] in
          Hashtbl.replace out p (concl :: cur);
          Hashtbl.replace indeg concl
            (Hashtbl.find indeg concl + 1))
        prem)
    bs;
  let ready = ref [] in
  Hashtbl.iter (fun c d -> if d = 0 then ready := c :: !ready) indeg;
  let seen = ref 0 in
  let rec drain () = match !ready with
    | [] -> ()
    | c :: rest ->
      ready := rest; incr seen;
      List.iter (fun d ->
          let k = Hashtbl.find indeg d - 1 in
          Hashtbl.replace indeg d k;
          if k = 0 then ready := d :: !ready)
        (try Hashtbl.find out c with Not_found -> []);
      drain () in
  drain ();
  if !seen <> List.length bs then
    fail "polarized orientation is not a DAG (Lemma 3.1)"
