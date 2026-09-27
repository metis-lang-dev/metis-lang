exception Ir_error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Ir_error s)) fmt

let case_lines name (em : Factorize.emitted) (prog : Ground.program)
    queries likelihoods =
  Bpn.check em;                (* no ill-typed net ships *)
  let out = ref [] in
  let line s = out := s :: !out in
  line ("C " ^ name);
  List.iter (fun (v, c) -> line (Printf.sprintf "V %s %d" v c))
    (List.sort (fun (a, _) (b, _) -> compare a b) em.e_cards);
  List.iter (fun (s : Factorize.site) ->
      line (Printf.sprintf "S %s %d %s%s%d" s.s_var
              (List.length s.s_parents)
              (String.concat " " s.s_parents)
              (if s.s_parents = [] then "" else " ")
              (List.length s.s_recs));
      List.iter (fun (r : Factorize.rec_) ->
          let b = Buffer.create 64 in
          Buffer.add_string b
            (Printf.sprintf "K %.17g %d" r.r_weight
               (List.length r.r_deps));
          List.iter (fun d ->
              Buffer.add_string b (" " ^ d)) r.r_deps;
          (match r.r_hook with
           | None -> Buffer.add_string b " 0"
           | Some h ->
             Buffer.add_string b
               (Printf.sprintf " 1 %s %d %d" h.hs_factor
                  (if h.hs_compl then 1 else 0)
                  (List.length h.hs_args));
             List.iter (fun a ->
                 Buffer.add_string b (" " ^ a)) h.hs_args;
             Buffer.add_string b
               (Printf.sprintf " %d" (List.length h.hs_base));
             List.iter (fun a ->
                 Buffer.add_string b (" " ^ a)) h.hs_base;
             Buffer.add_string b
               (Printf.sprintf " %d" (List.length h.hs_varats));
             List.iter (fun (a, pv) ->
                 Buffer.add_string b
                   (Printf.sprintf " %s %s" a pv)) h.hs_varats);
          line (Buffer.contents b))
        s.s_recs)
    em.e_sites;
  List.iter (fun (w : Factorize.write) ->
      line (Printf.sprintf "W %s %d %s %s %s" w.w_x w.w_card w.w_new
              (match w.w_old with Some o -> o | None -> "-")
              (String.concat " "
                 (List.map (function
                      | None -> "-" | Some v -> string_of_int v)
                     w.w_vals))))
    em.e_writes;
  List.iter (fun ((x, card, old), outcomes) ->
      line (Printf.sprintf "G %s %d %s %d %s" x card old
              (List.length outcomes)
              (String.concat " "
                 (List.map string_of_int
                    (List.sort compare outcomes)))))
    em.e_guards;
  List.iter (fun (a, v) ->
      let present = match List.assoc_opt a prog.init with
        | Some n when n > 0 -> 1 | _ -> 0 in
      line (Printf.sprintf "P %s %d" v present))
    em.e_unknown_vars;
  let scopes = Factorize.structure em in
  let resolve what a =
    match (try Hashtbl.find em.e_env a
           with Not_found -> Factorize.Cst 0) with
    | Factorize.Var v -> v
    | Factorize.Cst c ->
      fail "%s '%s' folded to the constant %d — corpus %ss must be \
            variables" what a c what in
  List.iter (fun q ->
      let v = resolve "query" q in
      let (_, _, order) = Elim.elim_cost scopes em.e_cards [v] in
      line (Printf.sprintf "O %s %d %s" v (List.length order)
              (String.concat " " order));
      line (Printf.sprintf "M %s %s" q v))    (* expectation: referee *)
    queries;
  List.iter (fun obs ->
      let clamps = List.map (fun (a, want) ->
          (resolve "likelihood atom" a, if want <> 0 then 1 else 0))
          (List.sort (fun (a, _) (b, _) -> compare a b) obs) in
      let (_, _, zorder) = Elim.elim_cost scopes em.e_cards [] in
      line (Printf.sprintf "Y %d %s" (List.length zorder)
              (String.concat " " zorder));
      let b = Buffer.create 32 in
      Buffer.add_string b
        (Printf.sprintf "Z %d" (List.length clamps));
      List.iter (fun (v, value) ->
          Buffer.add_string b (Printf.sprintf " %s %d" v value))
        clamps;
      line (Buffer.contents b))               (* expectation: referee *)
    likelihoods;
  line ".";
  List.rev !out
