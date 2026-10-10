(* SPDX-License-Identifier: Apache-2.0 *)
open Ast

exception Lang_error of string list

type weight_ref = {
  w_factor : string;
  w_args : string list;
  w_compl : bool }

type ports = {
  p_weights : (string * string list) list;
  p_reads : (string * Ast.read_pattern list) list;
  p_weight_refs : (string * weight_ref) list }

let is_upper s = s <> "" && s.[0] >= 'A' && s.[0] <= 'Z'

let pattern (a : atom) : Catalog.pattern =
  (a.pred, List.map term_str a.terms)

(* python-dict semantics: assignment overwrites, lookup by key *)
let set_assoc k v l =
  if List.mem_assoc k l then List.remove_assoc k l @ [(k, v)]
  else l @ [(k, v)]

(* ordered insertion: first occurrence wins; conflict -> finding *)
let infer_vars ?emit ?(conflict_code = "var-type-conflict") name atoms
    sigs findings =
  let vars = ref [] in
  List.iter (fun (a : atom) ->
      match List.assoc_opt a.pred sigs with
      | None -> ()        (* kernel typecheck reports undeclared *)
      | Some sig_ ->
        if List.length sig_ <> List.length a.terms then begin
          let text = Printf.sprintf "%s: %s arity %d != declared %d"
              name a.pred (List.length a.terms) (List.length sig_) in
          match emit with
          | Some e -> e "arity-mismatch" text
                        [ ("pred", a.pred);
                          ("expected", string_of_int (List.length sig_));
                          ("got", string_of_int (List.length a.terms)) ]
          | None -> findings := text :: !findings
        end else
          List.iter2 (fun t ty -> match t with
              | TConst _ -> ()
              | TVar v ->
                (match List.assoc_opt v !vars with
                 | None -> vars := !vars @ [(v, ty)]
                 | Some ty0 when ty0 <> ty ->
                   let text = Printf.sprintf
                       "%s: var %s typed both %s and %s" name v ty0 ty in
                   (match emit with
                    | Some e -> e conflict_code text
                                  [ ("var", v); ("type1", ty0);
                                    ("type2", ty) ]
                    | None -> findings := text :: !findings)
                 | Some _ -> ()))
            a.terms sig_)
    atoms;
  !vars

(* -- includes: literal splice, layers/stages adoption ----------------- *)

let rec resolve_in (c : Ast.catalog) base_dir seen =
  let layers = ref c.clayers and stages = ref c.cstages in
  let pairs = List.concat_map (fun (d, l) -> match d with
      | DInclude p ->
        let path = Filename.concat base_dir p in
        if List.mem path seen then begin
          let text = Printf.sprintf "include cycle at %s" p in
          Diag.emit (Diag.make "include-cycle" text
                       { Diag.s_loc = { Diag.file = l.file; line = l.line;
                                        col = l.col;
                                        decl = "include/" ^ p };
                         s_subject = [ decl_line d ]; s_context = [];
                         s_layers = "" }
                       [ ("path", p) ]);
          raise (Lang_error [ text ])
        end;
        let inc = Parser.parse_file path in
        let inc = resolve_in inc (Filename.dirname path)
            (path :: seen) in
        if !layers = [] then layers := inc.clayers;
        if !stages = [] then stages := inc.cstages;
        List.combine inc.cdecls inc.cdecl_locs
      | d -> [(d, l)])
      (List.combine c.cdecls c.cdecl_locs) in
  { c with clayers = !layers; cstages = !stages;
           cdecls = List.map fst pairs; cdecl_locs = List.map snd pairs }

let resolve_includes c base_dir = resolve_in c base_dir []

(* -- compilation ------------------------------------------------------ *)

(* a declaration's diagnostic slice (spec 08 D0; mirrors metispy
   compiler._Vocab.source): subject = its %% doc lines + one canonical
   line; context = the subject's preds in source order, first
   occurrence -> their namespaces -> their types as name + cardinality;
   the layers line rides separately *)
let source_of decls layers (l : Ast.loc) decl doc line (atoms : atom list) =
  let subject =
    (if doc = "" then []
     else List.map (fun x -> "%% " ^ x) (String.split_on_char '\n' doc))
    @ [ line ] in
  let find_pred n = List.find_opt (function
      | DPred (m, _, _) | DBwd (m, _) -> m = n | _ -> false) decls in
  let pdecls = List.fold_left (fun acc (a : atom) ->
      match find_pred a.pred with
      | Some d when not (List.memq d acc) -> acc @ [ d ]
      | _ -> acc) [] atoms in
  let ctx = ref (List.map decl_line pdecls) in
  let seen_ns = ref [] in
  List.iter (function
      | DPred (_, _, sp) when not (List.mem sp !seen_ns) ->
        (match List.find_opt (function
             | DNamespace (n, _, _) -> n = sp | _ -> false) decls with
         | Some nd -> seen_ns := !seen_ns @ [ sp ];
           ctx := !ctx @ [ decl_line nd ]
         | None -> ())
      | _ -> ()) pdecls;
  let seen_ty = ref [] in
  List.iter (fun d ->
      let args = match d with
        | DPred (_, a, _) | DBwd (_, a) -> a | _ -> [] in
      List.iter (fun ty ->
          if not (List.mem ty !seen_ty) then
            match List.find_opt (function
                | DType (n, _) -> n = ty | _ -> false) decls with
            | Some (DType (_, cs)) ->
              seen_ty := !seen_ty @ [ ty ];
              ctx := !ctx @ [ Printf.sprintf "type %s: %d constants" ty
                                (List.length cs) ]
            | _ -> ()) args) pdecls;
  { Diag.s_loc = { Diag.file = l.file; line = l.line; col = l.col; decl };
    s_subject = subject; s_context = !ctx;
    s_layers = if layers = [] then ""
      else Printf.sprintf "layers (%s)." (String.concat " " layers) }

(* the slice of a vocabulary declaration (catalog-level / admission
   diagnostics; mirrors metispy _Vocab.decl_source): subject = the
   decl itself; context = what it references (a pred's namespace, its
   arg types as name + cardinality) *)
let decl_source decls layers (l : Ast.loc) decl d =
  let ctx = ref [] in
  (match d with
   | DPred (_, _, sp) ->
     (match List.find_opt (function
          | DNamespace (n, _, _) -> n = sp | _ -> false) decls with
      | Some nd -> ctx := [ decl_line nd ]
      | None -> ())
   | _ -> ());
  (match d with
   | DPred (_, args, _) | DBwd (_, args) ->
     let seen = ref [] in
     List.iter (fun ty ->
         if not (List.mem ty !seen) then
           match List.find_opt (function
               | DType (n, _) -> n = ty | _ -> false) decls with
           | Some (DType (_, cs)) ->
             seen := !seen @ [ ty ];
             ctx := !ctx @ [ Printf.sprintf "type %s: %d constants" ty
                               (List.length cs) ]
           | _ -> ()) args
   | _ -> ());
  { Diag.s_loc = { Diag.file = l.file; line = l.line; col = l.col; decl };
    s_subject = [ decl_line d ]; s_context = !ctx;
    s_layers = if layers = [] then ""
      else Printf.sprintf "layers (%s)." (String.concat " " layers) }

(* the diagnostics of the last compile — and of a pack admission run
   right after it (Catalog.admit emits into the same sink) *)
let diagnostics () = Diag.collected ()

(* a CONSTANT in an argument position must be a member of the type
   that position declares (`eq(red,n7)` with eq(nat,nat): finding);
   positions whose type is not declared here are skipped — the kernel
   typecheck reports undeclared types (metispy: _check_consts) *)
let check_consts ?emit where (atoms : atom list) sigs types findings =
  List.iter (fun (a : atom) ->
      match List.assoc_opt a.pred sigs with
      | Some sig_ when List.length sig_ = List.length a.terms ->
        List.iteri (fun i (t, ty) ->
            match t, List.assoc_opt ty types with
            | TConst c, Some cs when not (List.mem c cs) ->
              let text = Printf.sprintf
                  "%s: constant '%s' is not a %s (%s argument %d)"
                  where c ty a.pred (i + 1) in
              (match emit with
               | Some e -> e "const-not-in-type" text
                             [ ("const", c); ("type", ty); ("pred", a.pred);
                               ("arg", string_of_int (i + 1)) ]
               | None -> findings := text :: !findings)
            | _ -> ())
          (List.combine a.terms sig_)
      | _ -> ())
    atoms

(* advisory, never gating; reset by every compile (metispy:
   CatalogDoc.warnings) *)
let last_warnings : string list ref = ref []
let warnings () = !last_warnings

(* a var occurring ONCE in a fact is almost always a typo
   (`plus(n0,N,M).` meant N twice): it silently means 'every value'.
   A deliberate don't-care is named Any or Any<Name> (the Ceptre
   corpus's own spelling) and stays silent. *)
let singleton_fact_vars (a : atom) sigs =
  let sig_ = match List.assoc_opt a.pred sigs with
    | Some s -> s | None -> [] in
  let names = List.filter_map (function
      | TVar v -> Some v | TConst _ -> None) a.terms in
  let starts_any v =
    String.length v >= 3 && String.sub v 0 3 = "Any" in
  List.concat (List.mapi (fun i t ->
      match t with
      | TVar v when List.length (List.filter (( = ) v) names) = 1
                    && not (starts_any v) ->
        let ty = match List.nth_opt sig_ i with
          | Some ty -> ty | None -> "value" in
        [ (Printf.sprintf
             "fact %s: var %s occurs once, so the fact holds for every \
              %s \xe2\x80\x94 if intended, name it Any%s (a leading Any \
              marks a don't-care)" (atom_str a) v ty v, v, ty) ]
      | _ -> []) a.terms)

let compile ?base (cat : Ast.catalog) : Catalog.t * ports =
  last_warnings := [];
  Diag.reset ();
  let findings = ref [] in
  let fail_now msgs = raise (Lang_error msgs) in
  if List.exists (function DInclude _ -> true | _ -> false)
      cat.cdecls then
    fail_now ["unresolved include — call resolve_includes first"];
  (match cat.cextends, base with
   | Some e, None ->
     let text = Printf.sprintf
         "catalog extends '%s' but no base catalog was provided" e in
     Diag.emit (Diag.make "extends-no-base" text
                  { Diag.s_loc = { Diag.file = ""; line = 0; col = 0;
                                   decl = "catalog/" ^ cat.cname };
                    s_subject = [ Printf.sprintf "extends %s." e ];
                    s_context = []; s_layers = "" }
                  [ ("base", e) ]);
     fail_now [ text ]
   | _ -> ());
  let (base_sigs, inherited_bwd, base_layers, base_stages,
       base_preds, base_types) =
    match base with
    | Some ((bcat : Catalog.t), (bsrc : Ast.catalog)) ->
      (List.filter_map (function
           | DPred (n, args, _) -> Some (n, args)
           | DBwd (n, args) -> Some (n, args)
           | _ -> None)
          bsrc.cdecls,
       bcat.k_bwd, bcat.k_layers, bcat.k_stages, bcat.k_preds,
       bcat.k_types)
    | None -> ([], [], [], [], [], []) in

  let vocab = cat.cdecls @ (match base with
      | Some (_, bsrc) -> bsrc.cdecls | None -> []) in
  let src_of = source_of vocab
      (if cat.clayers <> [] then cat.clayers else base_layers) in
  (* emit src code text data: the legacy finding (or warning) + the
     structured diagnostic, at the same point (metispy `emitter`) *)
  let emitter src code text data =
    let d = Diag.make code text src data in
    Diag.emit d;
    if d.Diag.severity = "error" then findings := text :: !findings
    else last_warnings := !last_warnings @ [ text ] in
  let decl_locs = List.combine cat.cdecls cat.cdecl_locs in
  (* decl-duplicate (a pre-pass, before sweep 1): one name, one
     declaration per kind — a second pred/bwd/type/namespace/port of a
     name is a finding at the SECOND occurrence (mirrors metispy) *)
  let first_seen = ref [] in
  List.iter (fun (d, (l : Ast.loc)) ->
      let kn = match d with
        | DPred (n, _, _) -> Some ("pred", n)
        | DBwd (n, _) -> Some ("bwd", n)
        | DType (n, _) -> Some ("type", n)
        | DNamespace (n, _, _) -> Some ("namespace", n)
        | DPort { pname; _ } -> Some ("port", pname)
        | _ -> None in
      match kn with
      | None -> ()
      | Some (kind, name) ->
        (match List.assoc_opt (kind, name) !first_seen with
         | None -> first_seen := !first_seen @ [ ((kind, name), l) ]
         | Some (l0 : Ast.loc) ->
           let where = Printf.sprintf "%s:%d"
               (if l0.file = "" then "<input>"
                else Filename.basename l0.file) l0.line in
           emitter
             (decl_source vocab
                (if cat.clayers <> [] then cat.clayers else base_layers)
                l (kind ^ "/" ^ name) d)
             "decl-duplicate"
             (Printf.sprintf "%s '%s' declared twice (first at %s)" kind
                name where)
             [ ("kind", kind); ("name", name); ("first", where) ]))
    decl_locs;

  (* sweep 1: vocabulary, ports (decl order) *)
  let types = ref [] and namespaces = ref [] in
  let preds = ref [] and sigs = ref base_sigs and bwd = ref [] in
  let p_weights = ref [] and p_reads = ref [] in
  List.iter (fun d -> match d with
      | DType (n, cs) -> types := !types @ [(n, cs)]
      | DNamespace (n, prod, cons) ->
        let cons = match cons with Some c -> c | None -> prod in
        namespaces := !namespaces @ [(n, (prod, cons))]
      | DPred (n, args, space) ->
        preds := !preds @ [(n, space)];
        sigs := set_assoc n args !sigs
      | DBwd (n, args) ->
        bwd := !bwd @ [n];
        sigs := set_assoc n args !sigs
      | DPort { pkind = Weight; pname; pargs; preads } ->
        p_weights := !p_weights @ [(pname, pargs)];
        (match preads with
         | Some ps -> p_reads := !p_reads @ [(pname, ps)]
         | None -> ())
      | DPort _ -> ()          (* guard/input/output: declared only *)
      | _ -> ())
    cat.cdecls;
  let is_bwd p = List.mem p !bwd || List.mem p inherited_bwd in
  let known_pred p =
    List.mem_assoc p !preds || List.mem_assoc p base_preds in


  (* read-scope validation (00-language-spec §5.2) *)
  List.iter (fun (factor, pats) ->
      let (pd, pl) = List.find (fun (d, _) -> match d with
          | DPort { pname; _ } -> pname = factor | _ -> false) decl_locs in
      let emit = emitter (src_of pl ("weight/" ^ factor) "" (decl_line pd)
                            (List.concat_map (fun (p : read_pattern) ->
                                 p.ratom :: p.rguards) pats)) in
      let formals = List.assoc factor !p_weights in
      let bad = List.filter (fun a -> not (is_upper a)) formals in
      if bad <> [] then
        emit "reads-formal-not-var"
          (Printf.sprintf "weight %s: reads needs var formals, got %s"
             factor (String.concat "," bad))
          [ ("port", factor); ("formals", String.concat "," bad) ];
      List.iter (fun (pat : read_pattern) ->
          List.iter (fun (a : atom) ->
              if a.persist then
                emit "reads-persist-marker"
                  (Printf.sprintf "weight %s: $ marker in reads %s" factor
                     (atom_str a))
                  [ ("port", factor); ("atom", atom_str a) ];
              (match List.assoc_opt a.pred !sigs with
               | Some s when List.length s <> List.length a.terms ->
                 emit "arity-mismatch"
                   (Printf.sprintf "weight %s: %s arity %d != declared %d"
                      factor a.pred (List.length a.terms) (List.length s))
                   [ ("pred", a.pred);
                     ("expected", string_of_int (List.length s));
                     ("got", string_of_int (List.length a.terms)) ]
               | _ -> ()))
            (pat.ratom :: pat.rguards);
          if not (known_pred pat.ratom.pred) then
            emit "reads-not-resource"
              (Printf.sprintf "weight %s: reads atom '%s' is not a \
                               declared resource predicate" factor
                 pat.ratom.pred)
              [ ("port", factor); ("pred", pat.ratom.pred) ];
          List.iter (fun (g : atom) ->
              if not (is_bwd g.pred) then
                emit "reads-guard-not-bwd"
                  (Printf.sprintf "weight %s: reads guard '%s' is not \
                                   declared bwd" factor g.pred)
                  [ ("port", factor); ("pred", g.pred) ])
            pat.rguards;
          let bound =
            formals
            @ List.concat_map (fun (g : atom) ->
                List.filter_map (function
                    | TVar v -> Some v | TConst _ -> None) g.terms)
              pat.rguards in
          List.iter (function
              | TVar v when not (List.mem v bound) ->
                emit "reads-var-unbound"
                  (Printf.sprintf "weight %s: reads var %s unbound (not \
                                   a formal, not guard-enumerated)"
                     factor v)
                  [ ("port", factor); ("var", v) ]
              | _ -> ())
            pat.ratom.terms)
        pats)
    !p_reads;

  (* sweep 2: entries (decl order); horn entries appended last *)
  let entries = ref [] and horn_entries = ref [] in
  let p_weight_refs = ref [] in
  let horn_layer =
    match cat.clayers with l :: _ -> l | [] -> "horn" in
  let add_horn ?(src = Diag.no_src) payload =
    horn_entries := !horn_entries @
      [{ Catalog.e_name =
           (* "horn/<head atom>" as metispy names it (str(atom)):
              clauses of one predicate stay distinguishable *)
           (let (hp, ha) = payload.Catalog.h_head in
            "horn/" ^ (if ha = [] then hp
                       else hp ^ "(" ^ String.concat "," ha ^ ")"));
         e_layer = horn_layer; e_comment = "Horn clause.";
         e_payload = Catalog.PHorn payload; e_src = src }] in
  List.iter2 (fun d dloc -> match d with
      | DFact a ->
        let fsrc = src_of dloc ("fact/" ^ a.pred) "" (decl_line d) [a] in
        let emit = emitter fsrc in
        if not (List.mem a.pred !bwd) then
          emit "fact-not-bwd"
            (Printf.sprintf "fact %s: predicate not declared bwd"
               (atom_str a))
            [ ("pred", a.pred) ]
        else begin
          (* a var in a fact is universally quantified over the type
             its position declares (`plus(n0,N,N).` = Pi N:nat) — the
             Ceptre/Twelf reading of a bodiless clause; typed like a
             rule var (conflicting positions are a finding) *)
          ignore (infer_vars ~emit ~conflict_code:"fact-var-conflict"
                    ("fact " ^ atom_str a) [a] !sigs findings);
          check_consts ~emit ("fact " ^ atom_str a) [a] !sigs
            (!types @ base_types) findings;
          List.iter (fun (text, v, ty) ->
              emit "fact-var-singleton" text [ ("var", v); ("type", ty) ])
            (singleton_fact_vars a !sigs);
          let vs = List.sort_uniq compare
              (List.filter_map (function
                   | TVar v -> Some v | TConst _ -> None) a.terms) in
          add_horn ~src:fsrc
            { h_head = pattern a; h_body = []; h_vars = vs }
        end
      | DHorn (h, body) ->
        let hsrc = src_of dloc ("horn/" ^ h.pred) "" (decl_line d)
            (h :: body) in
        check_consts ~emit:(emitter hsrc) ("horn " ^ atom_str h)
          (h :: body) !sigs (!types @ base_types) findings;
        let vs = List.sort_uniq compare
            (List.concat_map (fun (a : atom) ->
                 List.filter_map (function
                     | TVar v -> Some v | TConst _ -> None) a.terms)
               (h :: body)) in
        add_horn ~src:hsrc
          { h_head = pattern h; h_body = List.map pattern body;
            h_vars = vs }
      | DStage s ->
        List.iter (fun (r : rule) ->
            let body_atoms = List.filter_map (function
                | BAtom a -> Some a | BDistinct _ -> None) r.rbody in
            let atoms = body_atoms @ r.rhead in
            let rsrc = src_of r.rloc (s.sname ^ "/" ^ r.rname) r.rdoc
                (rule_line r)
                (List.filter (fun (a : atom) -> a.pred <> "one") atoms) in
            let emit = emitter rsrc in
            if String.trim r.rdoc = "" then
              emit "doc-missing"
                (Printf.sprintf "%s: missing %%%% doc (mandatory)" r.rname)
                [ ("rule", r.rname) ];
            let vars = infer_vars ~emit r.rname atoms !sigs findings in
            check_consts ~emit r.rname atoms !sigs (!types @ base_types)
              findings;
            List.iter (fun (a : atom) ->
                List.iter (function
                    | TVar v when List.assoc_opt v vars = None ->
                      emit "var-untypable"
                        (Printf.sprintf "%s: var %s untypable" r.rname v)
                        [ ("var", v) ]
                    | _ -> ())
                  a.terms)
              atoms;
            let consume = ref [] and persist = ref []
            and guards = ref [] in
            List.iter (function
                | BDistinct _ -> ()
                | BAtom a ->
                  if is_bwd a.pred then
                    guards := !guards @ [pattern a]
                  else if a.persist then
                    persist := !persist @ [pattern a]
                  else consume := !consume @ [pattern a])
              r.rbody;
            let weight = ref 1.0 in
            (match r.rweight with
             | None -> ()
             | Some (WVal v) -> weight := v
             | Some (WRef { factor; wargs; complement }) ->
               if List.assoc_opt factor !p_weights = None then
                 emit "weight-port-undeclared"
                   (Printf.sprintf "%s: weight port '%s' not declared"
                      r.rname factor)
                   [ ("port", factor) ];
               List.iter (function
                   | TVar v when List.assoc_opt v vars = None ->
                     emit "weight-arg-not-var"
                       (Printf.sprintf "%s: weight arg %s is not a rule var"
                          r.rname v)
                       [ ("port", factor); ("arg", v) ]
                   | _ -> ())
                 wargs;
               (match List.assoc_opt factor !p_reads,
                      List.assoc_opt factor !p_weights with
                | Some _, Some formals
                  when List.length wargs <> List.length formals ->
                  emit "arity-mismatch"
                    (Printf.sprintf "%s: weight %s takes %d args, got %d"
                       r.rname factor (List.length formals)
                       (List.length wargs))
                    [ ("pred", factor);
                      ("expected", string_of_int (List.length formals));
                      ("got", string_of_int (List.length wargs)) ]
                | _ -> ());
               p_weight_refs := !p_weight_refs @
                 [(r.rname,
                   { w_factor = factor;
                     w_args = List.map term_str wargs;
                     w_compl = complement })]);
            entries := !entries @
              [{ Catalog.e_name = r.rlayer ^ "/" ^ r.rname;
                 e_layer = r.rlayer; e_comment = r.rdoc;
                 e_src = rsrc;
                 e_payload = Catalog.PSchema {
                     cs_name = r.rname; cs_stage = s.sname;
                     cs_vars = vars;
                     cs_consume = !consume;
                     cs_produce = List.filter_map (fun (a : atom) ->
                         if a.pred = "one" then None    (* LL unit *)
                         else Some (pattern a)) r.rhead;
                     cs_persist = !persist;
                     cs_guards = !guards;
                     cs_distinct = List.filter_map (function
                         | BDistinct (a, b) -> Some (a, b)
                         | BAtom _ -> None) r.rbody;
                     cs_weight = !weight } }])
          s.srules
      | DLink l ->
        let atoms = l.lpre_atoms @ l.lpost_atoms in
        let lsrc = src_of dloc ("qui/" ^ l.lname) l.ldoc (decl_line d)
            atoms in
        let emit = emitter lsrc in
        if String.trim l.ldoc = "" then
          emit "doc-missing"
            (Printf.sprintf "%s: missing %%%% doc (mandatory)" l.lname)
            [ ("rule", l.lname) ];
        let vars = infer_vars ~emit l.lname atoms !sigs findings in
        check_consts ~emit l.lname atoms !sigs (!types @ base_types)
          findings;
        let consume = ref [] and persist = ref []
        and guards = ref [] in
        List.iter (fun (a : atom) ->
            if is_bwd a.pred then
              guards := !guards @ [pattern a]
            else if a.persist then persist := !persist @ [pattern a]
            else consume := !consume @ [pattern a])
          l.lpre_atoms;
        List.iter (fun (a : atom) ->
            if is_bwd a.pred then
              emit "link-post-bwd"
                (Printf.sprintf "%s: bwd '%s' in link post" l.lname a.pred)
                [ ("pred", a.pred) ])
          l.lpost_atoms;
        entries := !entries @
          [{ Catalog.e_name = l.llayer ^ "/" ^ l.lname;
             e_layer = l.llayer; e_comment = l.ldoc;
             e_src = lsrc;
             e_payload = Catalog.PLink {
                 ls_name = l.lname; ls_pre = l.lpre;
                 ls_post = l.lpost; ls_vars = vars;
                 ls_consume = !consume;
                 ls_produce = List.map pattern l.lpost_atoms;
                 ls_persist = !persist; ls_guards = !guards;
                 ls_distinct = [] } }]
      | _ -> ())
    cat.cdecls cat.cdecl_locs;

  if !findings <> [] then fail_now (List.rev !findings);

  let layers = if cat.clayers <> [] then cat.clayers
    else base_layers in
  let stages = if cat.cstages <> [] then cat.cstages
    else base_stages in
  let kcat = { Catalog.k_name = cat.cname; k_version = cat.cversion;
               k_layers = layers; k_stages = stages;
               k_types = !types; k_namespaces = !namespaces;
               k_preds = !preds; k_bwd = !bwd;
               k_entries = !entries @ !horn_entries;
               k_srcs = List.filter_map (fun (d, l) ->
                   let key = match d with
                     | DPred (n, _, _) -> Some ("pred/" ^ n)
                     | DBwd (n, _) -> Some ("bwd/" ^ n)
                     | DNamespace (n, _, _) -> Some ("namespace/" ^ n)
                     | DType (n, _) -> Some ("type/" ^ n)
                     | _ -> None in
                   Option.map (fun k ->
                       (k, decl_source vocab
                          (if cat.clayers <> [] then cat.clayers
                           else base_layers) l k d)) key)
                   decl_locs } in
  if cat.cextends = None then
    (match Catalog.typecheck kcat with
     | [] -> ()
     | fs -> fail_now fs);
  (kcat, { p_weights = !p_weights; p_reads = !p_reads;
           p_weight_refs = !p_weight_refs })
