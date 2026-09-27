type mset = (string * int) list

type event = {
  ev_name : string;
  ev_consume : mset; ev_produce : mset; ev_persist : mset;
  ev_weight : float;
  ev_pre : string option;
  ev_post : string option }

type program = {
  stages : (string * event list) list;
  links : event list;
  init_stage : string;
  init : mset }

let ground_atom ((pred, args) : Catalog.pattern) subst =
  if args = [] then pred
  else Printf.sprintf "%s(%s)" pred
      (String.concat ","
         (List.map (fun a ->
              match List.assoc_opt a subst with
              | Some c -> c | None -> a) args))

let multiset patterns subst : mset =
  List.fold_left (fun m p ->
      let a = ground_atom p subst in
      if List.mem_assoc a m then
        List.map (fun (k, n) -> if k = a then (k, n + 1) else (k, n)) m
      else m @ [(a, 1)])
    [] patterns

(* cartesian product, FIRST domain slowest / LAST fastest *)
let rec product = function
  | [] -> [[]]
  | d :: rest ->
    let tails = product rest in
    List.concat_map (fun c -> List.map (fun t -> c :: t) tails) d

let substitutions vars distinct guards
    (types : (string * string list) list) horn =
  let names = List.map fst vars in
  let domains = List.map (fun (_, ty) -> List.assoc ty types) vars in
  List.filter_map (fun combo ->
      let subst = List.combine names combo in
      if List.exists (fun (x, y) ->
          List.assoc x subst = List.assoc y subst) distinct
      then None
      else if List.for_all (fun (g, args) ->
          Horn.derivable horn
            (g, List.map (fun a ->
                 match List.assoc_opt a subst with
                 | Some c -> c | None -> a) args))
          guards
      then Some subst
      else None)
    (product domains)

let tag subst =
  String.concat ","
    (List.map (fun (v, c) -> Printf.sprintf "%s=%s" v c) subst)

let ground_name base subst =
  if subst = [] then base
  else Printf.sprintf "%s[%s]" base (tag subst)

let ground cat init_atoms =
  (match Catalog.typecheck cat with
   | [] -> ()
   | fs -> failwith ("catalog failed checks:\n  "
                     ^ String.concat "\n  " fs));
  let horn = Horn.make
      (List.filter_map (fun (e : Catalog.entry) ->
           match e.e_payload with
           | Catalog.PHorn h ->
             Some { Horn.head = h.h_head; body = h.h_body;
                    vars = h.h_vars }
           | _ -> None)
         cat.k_entries) in
  let stages = ref (List.map (fun s -> (s, ref [])) cat.k_stages) in
  let links = ref [] in
  List.iter (fun (e : Catalog.entry) ->
      match e.e_payload with
      | Catalog.PSchema sc ->
        let cell = List.assoc sc.cs_stage !stages in
        List.iter (fun subst ->
            cell := !cell @
              [{ ev_name = ground_name sc.cs_name subst;
                 ev_consume = multiset sc.cs_consume subst;
                 ev_produce = multiset sc.cs_produce subst;
                 ev_persist = multiset sc.cs_persist subst;
                 ev_weight = sc.cs_weight;
                 ev_pre = None; ev_post = None }])
          (substitutions sc.cs_vars sc.cs_distinct sc.cs_guards
             cat.k_types horn)
      | Catalog.PLink ls ->
        List.iter (fun subst ->
            links := !links @
              [{ ev_name = ground_name ls.ls_name subst;
                 ev_consume = multiset ls.ls_consume subst;
                 ev_produce = multiset ls.ls_produce subst;
                 ev_persist = multiset ls.ls_persist subst;
                 ev_weight = 1.0;
                 ev_pre = Some ls.ls_pre;
                 ev_post = Some ls.ls_post }])
          (substitutions ls.ls_vars ls.ls_distinct ls.ls_guards
             cat.k_types horn)
      | Catalog.PHorn _ -> ())
    cat.k_entries;
  { stages = List.map (fun (s, cell) -> (s, !cell)) !stages;
    links = !links;
    init_stage = (match cat.k_stages with
        | s :: _ -> s | [] -> failwith "no stages");
    init = List.filter (fun (_, n) -> n > 0) init_atoms }

let events p =
  List.concat_map snd p.stages @ p.links
