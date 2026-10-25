(* SPDX-License-Identifier: Apache-2.0 *)
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

(* GUARD-FIRST BINDING (eval-perf step 2h): the substitutions are the
   product's, enumerated depth first — FIRST var slowest, each over its
   type in declaration order — but a guard over a fact-only predicate
   narrows a var to the values its matching facts give as soon as the
   var is bound (its unbound positions free), so only prefixes some row
   can complete are formed. A pruned prefix has a guard no fact matches:
   the leaf check below refuses every completion of it too. The leaf
   check is unchanged, so the result is the old one, in its order. *)
let substitutions vars distinct guards
    (types : (string * string list) list) horn =
  let names = List.map fst vars in
  let domains = List.map (fun (_, ty) -> List.assoc ty types) vars in
  let leaf combo =
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
    else None in
  let is_var a = List.mem_assoc a vars in
  (* per var: the guards naming it *)
  let naming = List.map (fun v ->
      List.filter (fun (_, args) -> List.mem v args) guards) names in
  (* a var's candidates: its domain, narrowed by each fact guard naming
     it (bound vars as constants, the others free), in domain order *)
  let candidates v dom gs bound =
    let pattern (g, args) =
      (g, List.map (fun a ->
           if not (is_var a) then a
           else match List.assoc_opt a bound with
             | Some c -> c
             | None -> "?" ^ a) args) in
    List.fold_left (fun dom g ->
        match Horn.fact_values horn (pattern g) ("?" ^ v) with
        | None -> dom
        | Some vals ->
          let ok = Hashtbl.create 16 in
          List.iter (fun c -> Hashtbl.replace ok c ()) vals;
          List.filter (fun c -> Hashtbl.mem ok c) dom)
      dom gs in
  let out = ref [] in
  let rec go names domains naming bound rev_combo =
    match names, domains, naming with
    | [], _, _ ->
      (match leaf (List.rev rev_combo) with
       | Some s -> out := s :: !out
       | None -> ())
    | v :: names', dom :: domains', gs :: naming' ->
      List.iter (fun c ->
          go names' domains' naming' ((v, c) :: bound) (c :: rev_combo))
        (if gs = [] then dom else candidates v dom gs bound)
    | _ -> assert false in
  go names domains naming [] [];
  List.rev !out

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
  (* an abstract type left abstract: nothing to ground over (spec 12) *)
  (match Catalog.incomplete cat with
   | [] -> ()
   | fs -> raise (Catalog.Catalog_error fs));
  let horn = Horn.make
      (List.filter_map (fun (e : Catalog.entry) ->
           match e.e_payload with
           | Catalog.PHorn h ->
             Some { Horn.head = h.h_head; body = h.h_body;
                    vars = h.h_vars }
           | _ -> None)
         cat.k_entries) in
  (* events accumulate newest-first (O(1) per event) and are reversed
     once below: the order stays the normative one, without the
     O(E^2) list append (eval-perf step 1b) *)
  let stages = ref (List.map (fun s -> (s, ref [])) cat.k_stages) in
  let links = ref [] in
  List.iter (fun (e : Catalog.entry) ->
      match e.e_payload with
      | Catalog.PSchema sc ->
        let cell = List.assoc sc.cs_stage !stages in
        List.iter (fun subst ->
            cell :=
              { ev_name = ground_name sc.cs_name subst;
                ev_consume = multiset sc.cs_consume subst;
                ev_produce = multiset sc.cs_produce subst;
                ev_persist = multiset sc.cs_persist subst;
                ev_weight = sc.cs_weight;
                ev_pre = None; ev_post = None } :: !cell)
          (substitutions sc.cs_vars sc.cs_distinct sc.cs_guards
             cat.k_types horn)
      | Catalog.PLink ls ->
        List.iter (fun subst ->
            links :=
              { ev_name = ground_name ls.ls_name subst;
                ev_consume = multiset ls.ls_consume subst;
                ev_produce = multiset ls.ls_produce subst;
                ev_persist = multiset ls.ls_persist subst;
                ev_weight = 1.0;
                ev_pre = Some ls.ls_pre;
                ev_post = Some ls.ls_post } :: !links)
          (substitutions ls.ls_vars ls.ls_distinct ls.ls_guards
             cat.k_types horn)
      | Catalog.PHorn _ -> ())
    cat.k_entries;
  { stages = List.map (fun (s, cell) -> (s, List.rev !cell)) !stages;
    links = List.rev !links;
    init_stage = (match cat.k_stages with
        | s :: _ -> s | [] -> failwith "no stages");
    init = List.filter (fun (_, n) -> n > 0) init_atoms }

(* rev_append, not (@): the stdlib append is not tail-recursive and
   overflows the 8 MB stack at ~1M events (eval-perf step 1b) *)
let events p =
  List.rev_append (List.rev (List.concat_map snd p.stages)) p.links
