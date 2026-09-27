module SS = Set.Make (String)

let elim_cost scopes cards keep =
  let adj : (string, SS.t) Hashtbl.t = Hashtbl.create 64 in
  let get v = try Hashtbl.find adj v with Not_found -> SS.empty in
  List.iter (fun scope ->
      let s = SS.of_list scope in
      SS.iter (fun v ->
          Hashtbl.replace adj v (SS.union (get v) (SS.remove v s)))
        s)
    scopes;
  let card v = match List.assoc_opt v cards with
    | Some c -> c | None -> 2 in
  let todo = ref (Hashtbl.fold (fun v _ acc -> SS.add v acc) adj
                    SS.empty) in
  List.iter (fun k -> todo := SS.remove k !todo) keep;
  let width = ref 0 and ops = ref 0 and order = ref [] in
  while not (SS.is_empty !todo) do
    let fill v =
      let nb = SS.elements (SS.remove v (get v)) in
      let rec pairs = function
        | [] -> 0
        | x :: rest ->
          List.length
            (List.filter (fun y -> not (SS.mem y (get x))) rest)
          + pairs rest in
      pairs nb in
    (* min by (fill, name); SS.elements is sorted, strict < keeps
       the lexicographically first among fill-ties *)
    let v =
      match SS.elements !todo with
      | [] -> assert false
      | v0 :: rest ->
        let f0 = fill v0 in
        fst (List.fold_left (fun (bv, bf) u ->
            let fu = fill u in
            if fu < bf then (u, fu) else (bv, bf))
            (v0, f0) rest) in
    order := v :: !order;
    let nb = SS.remove v (get v) in
    width := max !width (SS.cardinal nb);
    let cost = SS.fold (fun u acc -> acc * card u) nb (card v) in
    ops := !ops + cost;
    SS.iter (fun x ->
        Hashtbl.replace adj x
          (SS.remove v (SS.union (get x) (SS.remove x nb))))
      nb;
    Hashtbl.remove adj v;
    todo := SS.remove v !todo
  done;
  (!width, !ops, List.rev !order)
