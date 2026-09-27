type pattern = string * string list

type clause_schema = {
  cs_name : string; cs_stage : string;
  cs_vars : (string * string) list;
  cs_consume : pattern list; cs_produce : pattern list;
  cs_persist : pattern list; cs_guards : pattern list;
  cs_distinct : (string * string) list;
  cs_weight : float }

type link_schema = {
  ls_name : string; ls_pre : string; ls_post : string;
  ls_vars : (string * string) list;
  ls_consume : pattern list; ls_produce : pattern list;
  ls_persist : pattern list; ls_guards : pattern list;
  ls_distinct : (string * string) list }

type horn_clause = {
  h_head : pattern; h_body : pattern list; h_vars : string list }

type payload =
  | PSchema of clause_schema
  | PLink of link_schema
  | PHorn of horn_clause

type entry = {
  e_name : string; e_layer : string; e_comment : string;
  e_payload : payload }

type t = {
  k_name : string; k_version : int;
  k_layers : string list; k_stages : string list;
  k_types : (string * string list) list;
  k_namespaces : (string * (string list * string list)) list;
  k_preds : (string * string) list;
  k_bwd : string list;
  k_entries : entry list }

let is_upper s = s <> "" && s.[0] >= 'A' && s.[0] <= 'Z'

let check_patterns e vars patterns mode preds namespaces bwd f =
  List.iter (fun (pred, args) ->
      if List.mem pred bwd then
        f := Printf.sprintf
            "%s: bwd predicate '%s' used as a resource (%s)"
            e.e_name pred mode :: !f
      else match List.assoc_opt pred preds with
        | None ->
          f := Printf.sprintf "%s: undeclared predicate '%s' (%s)"
              e.e_name pred mode :: !f
        | Some space ->
          let (produce, consume) =
            match List.assoc_opt space namespaces with
            | Some ns -> ns | None -> ([], []) in
          if mode = "produce" && not (List.mem e.e_layer produce) then
            f := Printf.sprintf
                "%s: layer '%s' may not produce '%s' (namespace '%s')"
                e.e_name e.e_layer pred space :: !f;
          if mode = "consume" && not (List.mem e.e_layer consume) then
            f := Printf.sprintf
                "%s: layer '%s' may not consume '%s' (namespace '%s')"
                e.e_name e.e_layer pred space :: !f;
          ignore args; ignore vars)
    patterns

let check_entry cat e =
  let f = ref [] in
  if String.trim e.e_comment = "" then
    f := Printf.sprintf "%s: missing comment (the unit a human \
                         approves is mandatory)" e.e_name :: !f;
  if not (List.mem e.e_layer cat.k_layers) then begin
    f := Printf.sprintf "%s: unknown layer '%s'" e.e_name e.e_layer
         :: !f;
    List.rev !f
  end else begin
    (match e.e_payload with
     | PHorn hc ->
       if not (List.mem (fst hc.h_head) cat.k_bwd) then
         f := Printf.sprintf
             "%s: horn head '%s' not a declared bwd predicate"
             e.e_name (fst hc.h_head) :: !f;
       List.iter (fun (bp, _) ->
           if not (List.mem bp cat.k_bwd) then
             f := Printf.sprintf
                 "%s: horn body '%s' not bwd — the Horn world is \
                  closed" e.e_name bp :: !f)
         hc.h_body
     | PSchema sc ->
       List.iter (fun (v, ty) ->
           if List.assoc_opt ty cat.k_types = None then
             f := Printf.sprintf "%s: var '%s' has unknown type '%s'"
                 e.e_name v ty :: !f)
         sc.cs_vars;
       if not (List.mem sc.cs_stage cat.k_stages) then
         f := Printf.sprintf "%s: unknown stage '%s'" e.e_name
             sc.cs_stage :: !f;
       check_patterns e sc.cs_vars sc.cs_consume "consume"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e sc.cs_vars sc.cs_produce "produce"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e sc.cs_vars sc.cs_persist "read"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       List.iter (fun (pred, args) ->
           if not (List.mem pred cat.k_bwd) then
             f := Printf.sprintf
                 "%s: guard on non-bwd predicate '%s' — guards are \
                  Horn premises only" e.e_name pred :: !f;
           List.iter (fun a ->
               if is_upper a && List.assoc_opt a sc.cs_vars = None
               then
                 f := Printf.sprintf
                     "%s: guard uses undeclared var '%s'" e.e_name a
                     :: !f)
             args)
         sc.cs_guards
     | PLink ls ->
       List.iter (fun (v, ty) ->
           if List.assoc_opt ty cat.k_types = None then
             f := Printf.sprintf "%s: var '%s' has unknown type '%s'"
                 e.e_name v ty :: !f)
         ls.ls_vars;
       if not (List.mem ls.ls_pre cat.k_stages)
       || not (List.mem ls.ls_post cat.k_stages) then
         f := Printf.sprintf
             "%s: link stage(s) '%s'->'%s' unknown" e.e_name
             ls.ls_pre ls.ls_post :: !f;
       check_patterns e ls.ls_vars ls.ls_consume "consume"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e ls.ls_vars ls.ls_produce "produce"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e ls.ls_vars ls.ls_persist "read"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       List.iter (fun (pred, _) ->
           if not (List.mem pred cat.k_bwd) then
             f := Printf.sprintf
                 "%s: guard on non-bwd predicate '%s' — guards are \
                  Horn premises only" e.e_name pred :: !f)
         ls.ls_guards);
    List.rev !f
  end

exception Catalog_error of string list

let typecheck cat =
  let f = ref [] in
  List.iter (fun (p, space) ->
      if List.assoc_opt space cat.k_namespaces = None then
        f := Printf.sprintf "predicate '%s': unknown namespace '%s'"
            p space :: !f;
      if List.mem p cat.k_bwd then
        f := Printf.sprintf
            "predicate '%s' declared both resource and bwd" p :: !f)
    cat.k_preds;
  List.iter (fun (name, (produce, consume)) ->
      List.iter (fun layer ->
          if not (List.mem layer cat.k_layers) then
            f := Printf.sprintf
                "namespace '%s': unknown layer '%s'" name layer :: !f)
        (produce @ List.filter (fun c -> not (List.mem c produce))
           consume))
    cat.k_namespaces;
  let head = List.rev !f in
  head @ List.concat_map (check_entry cat) cat.k_entries

let admit base pack =
  let f = ref [] in
  let add fmt = Printf.ksprintf (fun s -> f := s :: !f) fmt in
  List.iter (fun (t, _) ->
      if List.mem_assoc t base.k_types then
        add "pack redeclares type '%s'" t)
    pack.k_types;
  List.iter (fun (n, _) ->
      if List.mem_assoc n base.k_namespaces then
        add "pack redeclares namespace '%s'" n)
    pack.k_namespaces;
  List.iter (fun (p, space) ->
      if List.mem_assoc p base.k_preds || List.mem p base.k_bwd then
        add "pack redeclares predicate '%s'" p
      else if List.mem_assoc space base.k_namespaces then
        add "pack claims base namespace '%s' for '%s' — packs own \
             only their namespaces" space p)
    pack.k_preds;
  List.iter (fun p ->
      if List.mem p base.k_bwd || List.mem_assoc p base.k_preds then
        add "pack redeclares bwd predicate '%s'" p)
    pack.k_bwd;
  List.iter (fun s ->
      if not (List.mem s base.k_stages) then
        add "pack adds stage '%s' — stage set is the kernel's" s)
    pack.k_stages;
  if !f <> [] then raise (Catalog_error (List.rev !f));
  let merged = {
    k_name = base.k_name ^ "+" ^ pack.k_name;
    k_version = base.k_version;
    k_layers = base.k_layers; k_stages = base.k_stages;
    k_types = base.k_types @ pack.k_types;
    k_namespaces = base.k_namespaces @ pack.k_namespaces;
    k_preds = base.k_preds @ pack.k_preds;
    k_bwd = base.k_bwd @ pack.k_bwd;
    k_entries = base.k_entries @ pack.k_entries } in
  match typecheck merged with
  | [] -> merged
  | fs -> raise (Catalog_error fs)
