let sm_next (state : int64 ref) =
  state := Int64.add !state 0x9E3779B97F4A7C15L;
  let z = !state in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 30))
      0xBF58476D1CE4E5B9L in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 27))
      0x94D049BB133111EBL in
  Int64.logxor z (Int64.shift_right_logical z 31)

let sm_unit state =
  let z = Int64.shift_right_logical (sm_next state) 11 in
  Int64.to_float z *. (1.0 /. 9007199254740992.0)

type event_row = { kind : [`Clause | `Link]; stage : string;
                   ev : Ground.event }

let canonical_events (prog : Ground.program) =
  let rows = ref [] in
  List.iter (fun (s, clauses) ->
      List.iter (fun ev ->
          rows := { kind = `Clause; stage = s; ev } :: !rows)
        (List.sort (fun a b ->
             compare (Nets.clause_line a) (Nets.clause_line b))
            clauses))
    prog.stages;
  List.iter (fun (ev : Ground.event) ->
      let pre = match ev.ev_pre with Some p -> p | None -> "" in
      rows := { kind = `Link; stage = pre; ev } :: !rows)
    (List.sort (fun a b ->
         compare (Nets.link_line a) (Nets.link_line b))
        prog.links);
  Array.of_list (List.rev !rows)

let falling c n =
  let w = ref 1 in
  (try
     for i = 0 to n - 1 do
       w := !w * (c - i);
       if !w <= 0 then begin w := 0; raise Exit end
     done
   with Exit -> ());
  !w

let transition_count (ev : Ground.event) counts =
  let get a = try Hashtbl.find counts a with Not_found -> 0 in
  let w = ref 1 in
  (try
     List.iter (fun (a, n) ->
         w := !w * falling (get a) n;
         if !w = 0 then raise Exit)
       ev.Ground.ev_consume;
     List.iter (fun (a, n) ->
         let c = get a in
         for _ = 1 to n do w := !w * c done;
         if !w = 0 then raise Exit)
       ev.Ground.ev_persist
   with Exit -> ());
  !w

(* The one run loop. `pick stage candidates total` may resolve a
   CHOICE externally (the additive &, '#interactive' stages): Some i
   takes event i and consumes NO randomness; None falls through to
   the reference sampler draw. run_trace passes the constant-None
   pick, so the pinned sampler wire is byte-identical. *)
let run_trace_pick (prog : Ground.program) steps seed
    ~(pick : string -> (int * float) list -> float -> int option) =
  let events = canonical_events prog in
  let state = ref (Int64.of_int seed) in
  let counts : (string, int) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (a, n) -> Hashtbl.replace counts a n) prog.init;
  let stage = ref prog.init_stage in
  let trace = ref [] in
  (try
     for _ = 1 to steps do
       if !stage = "(done)" then raise Exit;
       let cands kind =
         let out = ref [] in
         Array.iteri (fun i r ->
             if r.kind = kind && r.stage = !stage then begin
               let n = transition_count r.ev counts in
               if n > 0 then begin
                 let w = r.ev.Ground.ev_weight
                         *. float_of_int n in
                 if w > 0.0 then out := (i, w) :: !out
               end
             end)
           events;
         List.rev !out in
       let ws = match cands `Clause with
         | [] -> cands `Link
         | ws -> ws in
       (match ws with
        | [] -> stage := "(done)"
        | _ ->
          let total = List.fold_left (fun acc (_, w) -> acc +. w)
              0.0 ws in
          let chosen =
            match pick !stage ws total with
            | Some i -> ref i
            | None ->
              let threshold = sm_unit state *. total in
              let chosen =
                ref (fst (List.nth ws (List.length ws - 1))) in
              let acc = ref 0.0 in
              (try
                 List.iter (fun (i, w) ->
                     acc := !acc +. w;
                     if threshold < !acc then begin
                       chosen := i; raise Exit
                     end)
                   ws
               with Exit -> ());
              chosen in
          trace := !chosen :: !trace;
          let r = events.(!chosen) in
          List.iter (fun (a, n) ->
              let c = (try Hashtbl.find counts a
                       with Not_found -> 0) - n in
              if c > 0 then Hashtbl.replace counts a c
              else Hashtbl.remove counts a)
            r.ev.Ground.ev_consume;
          List.iter (fun (a, n) ->
              Hashtbl.replace counts a
                ((try Hashtbl.find counts a
                  with Not_found -> 0) + n))
            r.ev.Ground.ev_produce;
          (match r.kind, r.ev.Ground.ev_post with
           | `Link, Some p -> stage := p
           | _ -> ()))
     done
   with Exit -> ());
  let final = Hashtbl.fold (fun a n acc ->
      if n > 0 then (a, n) :: acc else acc) counts [] in
  (List.rev !trace, (!stage, final))

let run_trace prog steps seed =
  run_trace_pick prog steps seed ~pick:(fun _ _ _ -> None)

let final_line seed (stage, kappa) =
  let items = List.sort compare
      (List.map (fun (a, n) -> Printf.sprintf "%s:%d" a n) kappa) in
  let tail = if items = [] then ""
    else " " ^ String.concat " " items in
  Printf.sprintf "F %d %s%s" seed stage tail
