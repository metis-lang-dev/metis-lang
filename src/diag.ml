type loc = { file : string; line : int; col : int; decl : string }

type src = {
  s_loc : loc; s_subject : string list; s_context : string list;
  s_layers : string }

type t = {
  code : string; severity : string; loc : loc;
  subject : string list; context : string list;
  data : (string * string) list; hint : string; text : string }

exception Defect of string

let context_cap = 12

(* BEGIN GENERATED from metispy metis/kernel/diagnostics.py by
   metispy/tools/gen_metisc_registry.py — never hand-edit *)
let registry = [
  ("doc-missing", ("error", "compile"));
  ("fact-var-conflict", ("error", "compile"));
  ("var-type-conflict", ("error", "compile"));
  ("var-untypable", ("error", "compile"));
  ("arity-mismatch", ("error", "compile"));
  ("fact-not-bwd", ("error", "compile"));
  ("link-post-bwd", ("error", "compile"));
  ("const-not-in-type", ("error", "compile"));
  ("fact-var-singleton", ("warning", "compile"));
  ("weight-port-undeclared", ("error", "compile"));
  ("weight-arg-not-var", ("error", "compile"));
  ("reads-formal-not-var", ("error", "compile"));
  ("reads-persist-marker", ("error", "compile"));
  ("reads-not-resource", ("error", "compile"));
  ("reads-guard-not-bwd", ("error", "compile"));
  ("reads-var-unbound", ("error", "compile"));
  ("include-cycle", ("error", "compile"));
  ("extends-no-base", ("error", "compile"));
  ("decl-duplicate", ("error", "compile"));
  ("containment-produce", ("error", "kernel"));
  ("containment-consume", ("error", "kernel"));
  ("pred-undeclared", ("error", "kernel"));
  ("bwd-as-resource", ("error", "kernel"));
  ("layer-unknown", ("error", "kernel"));
  ("var-type-unknown", ("error", "kernel"));
  ("stage-unknown", ("error", "kernel"));
  ("link-stage-unknown", ("error", "kernel"));
  ("horn-head-not-bwd", ("error", "kernel"));
  ("horn-body-not-bwd", ("error", "kernel"));
  ("pred-namespace-unknown", ("error", "kernel"));
  ("pred-resource-and-bwd", ("error", "kernel"));
  ("namespace-layer-unknown", ("error", "kernel"));
  ("pack-redeclares", ("error", "admission"));
  ("pack-claims-base-namespace", ("error", "admission"));
  ("pack-adds-stage", ("error", "admission"));
  ("rule-name-collision", ("warning", "loop"));
  ("provenance-shape", ("warning", "loop"));
  ("reads-undeclared", ("error", "runtime"));
  ("state-budget", ("note", "runtime"));
  ("horn-nonground", ("error", "runtime"));
  ("exact-unreachable", ("note", "runtime"));
  ("llm-endpoint", ("note", "runtime"));
  ("guard-not-bwd", ("error", "internal"));
  ("guard-var-undeclared", ("error", "internal"));
  ("comment-missing", ("error", "internal"));
  ("var-untyped", ("error", "internal"));
  ("kind-unknown", ("error", "internal")) ]

let gated_phases = [ "compile"; "kernel"; "admission" ]

let hint code data =
  let g k = match List.assoc_opt k data with Some v -> v | None -> "" in
  match code with
  | "doc-missing" ->
    String.concat "" [ "add a %% doc line above "; g "rule"; ": the doc is the approved text unit, mandatory on every rule and link" ]
  | "containment-produce" ->
    String.concat "" [ "layer '"; g "layer"; "' may not produce "; g "pred"; " (namespace '"; g "namespace"; "'): read it with $"; g "pred"; ", or declare the atom in a namespace your layer owns" ]
  | "containment-consume" ->
    String.concat "" [ "layer '"; g "layer"; "' may not consume "; g "pred"; " (namespace '"; g "namespace"; "'): read it with $"; g "pred"; " instead of spending it" ]
  | "fact-var-conflict" ->
    String.concat "" [ g "var"; " sits at a "; g "type1"; " and a "; g "type2"; " position: rename one occurrence, or fix the predicate signature" ]
  | "var-type-conflict" ->
    String.concat "" [ g "var"; " sits at a "; g "type1"; " and a "; g "type2"; " position: rename one occurrence, or fix the predicate signature" ]
  | "var-untypable" ->
    String.concat "" [ g "var"; " occurs in no typed position: use it in an atom whose signature types it, or drop it" ]
  | "arity-mismatch" ->
    String.concat "" [ g "pred"; " takes "; g "expected"; " argument(s), got "; g "got"; ": match the declared signature" ]
  | "fact-not-bwd" ->
    String.concat "" [ "a fact is Horn knowledge: declare "; g "pred"; " with `bwd`, or make it an #init resource" ]
  | "link-post-bwd" ->
    String.concat "" [ "a link may not produce the Horn atom "; g "pred"; ": bwd predicates are knowledge, not state" ]
  | "const-not-in-type" ->
    String.concat "" [ "'"; g "const"; "' is not a constant of "; g "type"; ": add it to the type, or fix argument "; g "arg"; " of "; g "pred" ]
  | "fact-var-singleton" ->
    String.concat "" [ "if intended, name it Any"; g "var"; " (a leading Any marks a don't-care); otherwise repeat the variable where it belongs" ]
  | "weight-port-undeclared" ->
    String.concat "" [ "declare the port (`weight "; g "port"; "(...) reads "; "{"; "..."; "}"; ".`), or drop the @w reference" ]
  | "weight-arg-not-var" ->
    String.concat "" [ "pass rule variables to "; g "port"; ": "; g "arg"; " is not a variable of this rule" ]
  | "reads-formal-not-var" ->
    String.concat "" [ "the formals of weight "; g "port"; " must be variables (got "; g "formals"; ")" ]
  | "reads-persist-marker" ->
    String.concat "" [ "drop the $ in "; g "atom"; ": a reads scope is already read-only" ]
  | "reads-not-resource" ->
    String.concat "" [ "a reads scope names resource predicates only: declare "; g "pred"; " with `pred`, or drop it from the scope of "; g "port" ]
  | "reads-guard-not-bwd" ->
    String.concat "" [ "a reads guard must be a bwd predicate: declare "; g "pred"; " with `bwd`" ]
  | "reads-var-unbound" ->
    String.concat "" [ "bind "; g "var"; ": make it a formal of "; g "port"; ", or enumerate it with a guard" ]
  | "include-cycle" ->
    String.concat "" [ "break the include cycle at "; g "path" ]
  | "extends-no-base" ->
    String.concat "" [ "compile this pack against its base catalog "; g "base" ]
  | "decl-duplicate" ->
    String.concat "" [ "a name is declared once per kind: remove this "; g "kind"; " declaration of "; g "name"; ", or rename it (first at "; g "first"; ")" ]
  | "pred-undeclared" ->
    String.concat "" [ "declare "; g "pred"; ": `pred "; g "pred"; "(...) : <namespace>.`" ]
  | "bwd-as-resource" ->
    String.concat "" [ g "pred"; " is a bwd predicate: use it as a guard premise only, never as a resource ("; g "mode"; ")" ]
  | "layer-unknown" ->
    String.concat "" [ "add "; g "layer"; " to the catalog's layers (...), or tag the rule with a declared layer" ]
  | "var-type-unknown" ->
    String.concat "" [ "declare type "; g "type"; ", or fix the signature that names it" ]
  | "stage-unknown" ->
    String.concat "" [ "add "; g "stage"; " to stages (...)" ]
  | "link-stage-unknown" ->
    String.concat "" [ "declare both link stages ("; g "pre"; ", "; g "post"; ") in stages (...)" ]
  | "horn-head-not-bwd" ->
    String.concat "" [ "a Horn rule may only derive bwd predicates: declare "; g "pred"; " with `bwd`" ]
  | "horn-body-not-bwd" ->
    String.concat "" [ "the Horn world is closed: "; g "pred"; " must be a bwd predicate" ]
  | "pred-namespace-unknown" ->
    String.concat "" [ "declare namespace "; g "namespace"; ", or move "; g "pred"; " into a declared one" ]
  | "pred-resource-and-bwd" ->
    String.concat "" [ g "pred"; " is declared both `pred` and `bwd`: keep one" ]
  | "namespace-layer-unknown" ->
    String.concat "" [ "add "; g "layer"; " to layers (...), or drop it from namespace "; g "namespace" ]
  | "pack-redeclares" ->
    String.concat "" [ "a pack may only add: rename the pack's "; g "kind"; " "; g "name" ]
  | "pack-claims-base-namespace" ->
    String.concat "" [ "a pack owns only its own namespaces: put "; g "pred"; " in a namespace the pack declares" ]
  | "pack-adds-stage" ->
    String.concat "" [ "a pack may not add stage "; g "stage"; ": the stage set is the base's" ]
  | "rule-name-collision" ->
    String.concat "" [ "rename one of the "; g "count"; " rules named "; g "rule"; ": trace events and the debug sidecar read SHORT names" ]
  | "provenance-shape" ->
    String.concat "" [ "declare `provenance text \"<ref>\" \"<date>\".`: the formalization contract records its source" ]
  | "reads-undeclared" ->
    String.concat "" [ "add "; g "atom"; " to the port's reads scope, or stop reading it in the binding: the declared scope is the contract" ]
  | "state-budget" ->
    String.concat "" [ "lower the horizon (try: "; g "retry"; "), or this is clique-tree / factored territory" ]
  | "horn-nonground" ->
    String.concat "" [ "guard the unbound variable with a predicate that enumerates it" ]
  | "exact-unreachable" ->
    String.concat "" [ "the sampled counts stand; for exact numbers lower #steps or shrink the scene ("; g "reason"; ")" ]
  | "llm-endpoint" ->
    String.concat "" [ g "problem"; ": start the server or `ollama pull "; g "model"; "`, or pick another endpoint with `llm`" ]
  | _ -> ""
(* END GENERATED *)

let no_src = { s_loc = { file = ""; line = 0; col = 0; decl = "" };
               s_subject = []; s_context = []; s_layers = "" }

let layer_codes = [ "containment-produce"; "containment-consume";
                    "layer-unknown"; "namespace-layer-unknown" ]

(* The var-type-unknown slice (spec 08 A2): only the pred/bwd lines
   whose signature names the unknown type -- where the type was named;
   the rest of the rule's closure overflowed the cap on wide rules.
   Order kept; byte parity with metispy (diagnostics._naming_type). *)
let naming_type context ty =
  let names_it ln =
    let starts p = String.length ln >= String.length p
                   && String.sub ln 0 (String.length p) = p in
    (starts "pred " || starts "bwd ")
    && (match String.index_opt ln '(', String.index_opt ln ')' with
        | Some i, Some j when j > i ->
          String.split_on_char ',' (String.sub ln (i + 1) (j - i - 1))
          |> List.exists (fun a -> String.trim a = ty)
        | _ -> false) in
  List.filter names_it context

let make code text src data =
  let severity = match List.assoc_opt code registry with
    | Some (s, _) -> s
    | None -> raise (Defect ("unregistered diagnostic code '" ^ code
                             ^ "'")) in
  let context =
    if List.mem code layer_codes && src.s_layers <> "" then
      src.s_context @ [ src.s_layers ]
    else src.s_context in
  let context =
    if code = "var-type-unknown" then
      naming_type context
        (match List.assoc_opt "type" data with Some t -> t | None -> "")
    else context in
  if List.length context > context_cap then
    raise (Defect (Printf.sprintf
                     "%s @ %s: context of %d lines exceeds the cap of %d"
                     code src.s_loc.decl (List.length context)
                     context_cap));
  { code; severity; loc = src.s_loc; subject = src.s_subject; context;
    data; hint = hint code data; text }

let sink : t list ref = ref []
let reset () = sink := []
let emit d = sink := d :: !sink
let collected () = List.rev !sink

let render_text d =
  let b = Buffer.create 256 in
  if d.loc.line > 0 then begin
    let f = if d.loc.file = "" then "<input>"
      else Filename.basename d.loc.file in
    Buffer.add_string b
      (Printf.sprintf "%s %s @ %s:%d:%d (%s)\n" d.severity d.code f
         d.loc.line d.loc.col d.loc.decl)
  end else      (* no source position (runtime notes, header-level) *)
    Buffer.add_string b
      (Printf.sprintf "%s %s (%s)\n" d.severity d.code d.loc.decl);
  List.iter (fun s -> Buffer.add_string b ("  " ^ s ^ "\n")) d.subject;
  List.iter (fun c -> Buffer.add_string b ("  | " ^ c ^ "\n")) d.context;
  if d.hint <> "" then Buffer.add_string b ("  -> " ^ d.hint ^ "\n");
  Buffer.contents b

(* JSON string exactly as python json.dumps(ensure_ascii=False):
   escape the double quote, the backslash and control chars (short
   forms for newline, return, tab, backspace, formfeed; else u00XX);
   everything else raw *)
let json_str s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c -> match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | '\b' -> Buffer.add_string b "\\b"
      | '\012' -> Buffer.add_string b "\\f"
      | c when Char.code c < 0x20 ->
        Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

let json_list l = "[" ^ String.concat "," (List.map json_str l) ^ "]"

let to_json d =
  Printf.sprintf
    "{\"code\":%s,\"severity\":%s,\"loc\":{\"file\":%s,\"line\":%d,\
     \"col\":%d,\"decl\":%s},\"subject\":%s,\"context\":%s,\
     \"data\":{%s},\"hint\":%s,\"text\":%s}"
    (json_str d.code) (json_str d.severity) (json_str d.loc.file)
    d.loc.line d.loc.col (json_str d.loc.decl) (json_list d.subject)
    (json_list d.context)
    (String.concat ","
       (List.map (fun (k, v) -> json_str k ^ ":" ^ json_str v) d.data))
    (json_str d.hint) (json_str d.text)
