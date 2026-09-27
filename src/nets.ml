let mset_str (m : Ground.mset) =
  let items = List.sort compare
      (List.filter_map (fun (a, n) ->
           if n > 0 then Some (Printf.sprintf "%s:%d" a n) else None)
          m) in
  if items = [] then "-" else String.concat "," items

let clause_line (ev : Ground.event) =
  Printf.sprintf "c %s ; %s ; %s ; w %.17g"
    (mset_str ev.ev_consume) (mset_str ev.ev_produce)
    (mset_str ev.ev_persist) ev.ev_weight

let link_line (ev : Ground.event) =
  Printf.sprintf "l %s %s ; %s ; %s ; %s ; w %.17g"
    (match ev.ev_pre with Some p -> p | None -> "")
    (match ev.ev_post with Some p -> p | None -> "")
    (mset_str ev.ev_consume) (mset_str ev.ev_produce)
    (mset_str ev.ev_persist) ev.ev_weight

let canonical_string (prog : Ground.program) =
  let lines = ref ["metis-canonical 1"] in
  let add l = lines := l :: !lines in
  List.iter (fun (s, clauses) ->
      add ("stage " ^ s);
      List.iter add
        (List.sort compare (List.map clause_line clauses)))
    prog.stages;
  List.iter add
    (List.sort compare (List.map link_line prog.links));
  add ("init-stage " ^ prog.init_stage);
  List.iter add
    (List.sort compare
       (List.filter_map (fun (a, n) ->
            if n > 0 then Some (Printf.sprintf "i %s:%d" a n)
            else None)
           prog.init));
  String.concat "\n" (List.rev !lines) ^ "\n"

let program_key prog = Sha256.hex (canonical_string prog)
