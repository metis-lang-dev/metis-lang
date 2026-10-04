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
  e_payload : payload;
  e_src : Diag.src }   (* the decl's diagnostic slice (spec 08) *)

type t = {
  k_name : string; k_version : int;
  k_layers : string list; k_stages : string list;
  k_types : (string * string list) list;
  k_namespaces : (string * (string list * string list)) list;
  k_preds : (string * string) list;
  k_bwd : string list;
  k_entries : entry list;
  k_srcs : (string * Diag.src) list }
  (* decl slices for catalog-level / admission diagnostics (spec 08),
     keyed "pred/x", "bwd/x", "namespace/y", "type/t" *)

let is_upper s = s <> "" && s.[0] >= 'A' && s.[0] <= 'Z'

(* the legacy finding string + its structured diagnostic, together
   (metispy typing._emit) *)
let emit f code text src data =
  f := text :: !f;
  Diag.emit (Diag.make code text src data)

let check_patterns e vars patterns mode preds namespaces bwd f =
  List.iter (fun (pred, args) ->
      if List.mem pred bwd then
        emit f "bwd-as-resource"
          (Printf.sprintf "%s: bwd predicate '%s' used as a resource (%s)"
             e.e_name pred mode) e.e_src
          [ ("pred", pred); ("mode", mode) ]
      else match List.assoc_opt pred preds with
        | None ->
          emit f "pred-undeclared"
            (Printf.sprintf "%s: undeclared predicate '%s' (%s)"
               e.e_name pred mode) e.e_src
            [ ("pred", pred); ("mode", mode) ]
        | Some space ->
          let (produce, consume) =
            match List.assoc_opt space namespaces with
            | Some ns -> ns | None -> ([], []) in
          List.iter (fun (m, allowed) ->
              if mode = m && not (List.mem e.e_layer allowed) then
                emit f ("containment-" ^ m)
                  (Printf.sprintf
                     "%s: layer '%s' may not %s '%s' (namespace '%s')"
                     e.e_name e.e_layer m pred space) e.e_src
                  [ ("layer", e.e_layer); ("pred", pred);
                    ("namespace", space) ])
            [ ("produce", produce); ("consume", consume) ];
          ignore args; ignore vars)
    patterns

let check_entry cat e =
  let f = ref [] in
  let src = e.e_src in
  if String.trim e.e_comment = "" then
    emit f "comment-missing"
      (Printf.sprintf "%s: missing comment (the unit a human approves \
                       is mandatory)" e.e_name) src
      [ ("entry", e.e_name) ];
  if not (List.mem e.e_layer cat.k_layers) then begin
    emit f "layer-unknown"
      (Printf.sprintf "%s: unknown layer '%s'" e.e_name e.e_layer) src
      [ ("layer", e.e_layer) ];
    List.rev !f
  end else begin
    let var_types vars =
      List.iter (fun (v, ty) ->
          if List.assoc_opt ty cat.k_types = None then
            emit f "var-type-unknown"
              (Printf.sprintf "%s: var '%s' has unknown type '%s'"
                 e.e_name v ty) src [ ("var", v); ("type", ty) ])
        vars in
    let guard_not_bwd pred =
      if not (List.mem pred cat.k_bwd) then
        emit f "guard-not-bwd"
          (Printf.sprintf "%s: guard on non-bwd predicate '%s' — guards \
                           are Horn premises only" e.e_name pred) src
          [ ("pred", pred) ] in
    (match e.e_payload with
     | PHorn hc ->
       if not (List.mem (fst hc.h_head) cat.k_bwd) then
         emit f "horn-head-not-bwd"
           (Printf.sprintf "%s: horn head '%s' not a declared bwd \
                            predicate" e.e_name (fst hc.h_head)) src
           [ ("pred", fst hc.h_head) ];
       List.iter (fun (bp, _) ->
           if not (List.mem bp cat.k_bwd) then
             emit f "horn-body-not-bwd"
               (Printf.sprintf "%s: horn body '%s' not bwd — the Horn \
                                world is closed" e.e_name bp) src
               [ ("pred", bp) ])
         hc.h_body
     | PSchema sc ->
       var_types sc.cs_vars;
       if not (List.mem sc.cs_stage cat.k_stages) then
         emit f "stage-unknown"
           (Printf.sprintf "%s: unknown stage '%s'" e.e_name sc.cs_stage)
           src [ ("stage", sc.cs_stage) ];
       check_patterns e sc.cs_vars sc.cs_consume "consume"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e sc.cs_vars sc.cs_produce "produce"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e sc.cs_vars sc.cs_persist "read"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       List.iter (fun (pred, args) ->
           guard_not_bwd pred;
           List.iter (fun a ->
               if is_upper a && List.assoc_opt a sc.cs_vars = None then
                 emit f "guard-var-undeclared"
                   (Printf.sprintf "%s: guard uses undeclared var '%s'"
                      e.e_name a) src [ ("var", a) ])
             args)
         sc.cs_guards
     | PLink ls ->
       var_types ls.ls_vars;
       if not (List.mem ls.ls_pre cat.k_stages)
       || not (List.mem ls.ls_post cat.k_stages) then
         emit f "link-stage-unknown"
           (Printf.sprintf "%s: link stage(s) '%s'->'%s' unknown"
              e.e_name ls.ls_pre ls.ls_post) src
           [ ("pre", ls.ls_pre); ("post", ls.ls_post) ];
       check_patterns e ls.ls_vars ls.ls_consume "consume"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e ls.ls_vars ls.ls_produce "produce"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       check_patterns e ls.ls_vars ls.ls_persist "read"
         cat.k_preds cat.k_namespaces cat.k_bwd f;
       List.iter (fun (pred, _) -> guard_not_bwd pred) ls.ls_guards);
    List.rev !f
  end

exception Catalog_error of string list

let src_of cat key = match List.assoc_opt key cat.k_srcs with
  | Some s -> s | None -> Diag.no_src

let typecheck cat =
  let f = ref [] in
  List.iter (fun (p, space) ->
      if List.assoc_opt space cat.k_namespaces = None then
        emit f "pred-namespace-unknown"
          (Printf.sprintf "predicate '%s': unknown namespace '%s'" p space)
          (src_of cat ("pred/" ^ p))
          [ ("pred", p); ("namespace", space) ];
      if List.mem p cat.k_bwd then
        emit f "pred-resource-and-bwd"
          (Printf.sprintf "predicate '%s' declared both resource and bwd" p)
          (src_of cat ("pred/" ^ p)) [ ("pred", p) ])
    cat.k_preds;
  List.iter (fun (name, (produce, consume)) ->
      List.iter (fun layer ->
          if not (List.mem layer cat.k_layers) then
            emit f "namespace-layer-unknown"
              (Printf.sprintf "namespace '%s': unknown layer '%s'" name
                 layer)
              (src_of cat ("namespace/" ^ name))
              [ ("namespace", name); ("layer", layer) ])
        (* sorted, deterministic (metispy _layer_order) *)
        (List.sort_uniq compare (produce @ consume)))
    cat.k_namespaces;
  let head = List.rev !f in
  head @ List.concat_map (check_entry cat) cat.k_entries

let admit base pack =
  let f = ref [] in
  let ps = src_of pack in
  List.iter (fun (t, _) ->
      if List.mem_assoc t base.k_types then
        emit f "pack-redeclares"
          (Printf.sprintf "pack redeclares type '%s'" t) (ps ("type/" ^ t))
          [ ("kind", "type"); ("name", t) ])
    pack.k_types;
  List.iter (fun (n, _) ->
      if List.mem_assoc n base.k_namespaces then
        emit f "pack-redeclares"
          (Printf.sprintf "pack redeclares namespace '%s'" n)
          (ps ("namespace/" ^ n)) [ ("kind", "namespace"); ("name", n) ])
    pack.k_namespaces;
  List.iter (fun (p, space) ->
      if List.mem_assoc p base.k_preds || List.mem p base.k_bwd then
        emit f "pack-redeclares"
          (Printf.sprintf "pack redeclares predicate '%s'" p)
          (ps ("pred/" ^ p)) [ ("kind", "predicate"); ("name", p) ]
      else if List.mem_assoc space base.k_namespaces then
        emit f "pack-claims-base-namespace"
          (Printf.sprintf "pack claims base namespace '%s' for '%s' — \
                           packs own only their namespaces" space p)
          (ps ("pred/" ^ p)) [ ("pred", p); ("namespace", space) ])
    pack.k_preds;
  List.iter (fun p ->
      if List.mem p base.k_bwd || List.mem_assoc p base.k_preds then
        emit f "pack-redeclares"
          (Printf.sprintf "pack redeclares bwd predicate '%s'" p)
          (ps ("bwd/" ^ p)) [ ("kind", "bwd predicate"); ("name", p) ])
    pack.k_bwd;
  List.iter (fun s ->
      if not (List.mem s base.k_stages) then
        emit f "pack-adds-stage"
          (Printf.sprintf "pack adds stage '%s' — stage set is the \
                           kernel's" s)
          { Diag.s_loc = { Diag.file = ""; line = 0; col = 0;
                           decl = "stages" };
            s_subject = [ Printf.sprintf "stages (%s)."
                            (String.concat " " pack.k_stages) ];
            s_context = []; s_layers = "" }
          [ ("stage", s) ])
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
    k_entries = base.k_entries @ pack.k_entries;
    k_srcs = pack.k_srcs @ base.k_srcs } in
  match typecheck merged with
  | [] -> merged
  | fs -> raise (Catalog_error fs)
