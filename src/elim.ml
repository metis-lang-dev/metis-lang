(* SPDX-License-Identifier: Apache-2.0 *)
module SS = Set.Make (String)

(* (fill, name): the normative order of the min-fill choice — the least
   fill, ties to the lexicographically first name *)
module FS = Set.Make (struct
    type t = int * string
    let compare = compare
  end)

(* INCREMENTAL MIN-FILL (eval-perf step 2i, P10): the same choice as a
   rescan of every remaining variable per elimination, kept in an
   ordered set of (fill, name). Eliminating v changes the neighbourhood
   of v's neighbours only, and the adjacency among the neighbours of a
   variable only if that variable is adjacent to one of v's neighbours:
   so only nb ∪ N(nb) is re-filled. *)
let elim_cost scopes cards keep =
  let adj : (string, SS.t) Hashtbl.t = Hashtbl.create 64 in
  let get v = try Hashtbl.find adj v with Not_found -> SS.empty in
  List.iter (fun scope ->
      let s = SS.of_list scope in
      SS.iter (fun v ->
          Hashtbl.replace adj v (SS.union (get v) (SS.remove v s)))
        s)
    scopes;
  (* the first binding of a name wins, as List.assoc_opt *)
  let cardt = Hashtbl.create 64 in
  List.iter (fun (v, c) ->
      if not (Hashtbl.mem cardt v) then Hashtbl.add cardt v c) cards;
  let card v = match Hashtbl.find_opt cardt v with
    | Some c -> c | None -> 2 in
  let todo = ref (Hashtbl.fold (fun v _ acc -> SS.add v acc) adj
                    SS.empty) in
  List.iter (fun k -> todo := SS.remove k !todo) keep;
  let fill v =
    let nb = SS.elements (SS.remove v (get v)) in
    let rec pairs = function
      | [] -> 0
      | x :: rest ->
        List.length
          (List.filter (fun y -> not (SS.mem y (get x))) rest)
        + pairs rest in
    pairs nb in
  let fills : (string, int) Hashtbl.t = Hashtbl.create 64 in
  let queue = ref FS.empty in
  let refill u =
    (match Hashtbl.find_opt fills u with
     | Some f -> queue := FS.remove (f, u) !queue
     | None -> ());
    let f = fill u in
    Hashtbl.replace fills u f;
    queue := FS.add (f, u) !queue in
  SS.iter refill !todo;
  let width = ref 0 and ops = ref 0 and order = ref [] in
  while not (FS.is_empty !queue) do
    let (_, v) as top = FS.min_elt !queue in
    queue := FS.remove top !queue;
    Hashtbl.remove fills v;
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
    todo := SS.remove v !todo;
    let touched = SS.fold (fun x acc -> SS.union (get x) acc) nb nb in
    SS.iter (fun u -> if SS.mem u !todo then refill u) touched
  done;
  (!width, !ops, List.rev !order)
