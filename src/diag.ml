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

let registry = [
  ("doc-missing", ("error", true));
  ("containment-produce", ("error", true));
  ("containment-consume", ("error", true));
  ("fact-var-conflict", ("error", true));
  ("fact-not-bwd", ("error", false));
  ("var-untypable", ("error", false));
  ("fact-var-singleton", ("warning", false));
  ("const-not-in-type", ("error", false));
  ("rule-name-collision", ("warning", false));
  ("provenance-shape", ("warning", false));
  ("reads-undeclared", ("warning", false));
  ("state-budget", ("note", false));
  ("horn-nonground", ("error", false));
  ("exact-unreachable", ("note", false));
  ("llm-endpoint", ("note", false)) ]

let hint code data =
  let g k = match List.assoc_opt k data with Some v -> v | None -> "" in
  match code with
  | "doc-missing" ->
    Printf.sprintf "add a %%%% doc line above %s: the doc is the \
                    approved text unit, mandatory on every rule and \
                    link" (g "rule")
  | "containment-produce" ->
    Printf.sprintf "layer '%s' may not produce %s (namespace '%s'): \
                    read it with $%s, or declare the atom in a \
                    namespace your layer owns"
      (g "layer") (g "pred") (g "namespace") (g "pred")
  | "containment-consume" ->
    Printf.sprintf "layer '%s' may not consume %s (namespace '%s'): \
                    read it with $%s instead of spending it"
      (g "layer") (g "pred") (g "namespace") (g "pred")
  | "fact-var-conflict" ->
    Printf.sprintf "%s sits at a %s and a %s position: rename one \
                    occurrence, or fix the predicate signature"
      (g "var") (g "type1") (g "type2")
  | _ -> ""

let no_src = { s_loc = { file = ""; line = 0; col = 0; decl = "" };
               s_subject = []; s_context = []; s_layers = "" }

let layer_codes = [ "containment-produce"; "containment-consume" ]

let make code text src data =
  let severity = match List.assoc_opt code registry with
    | Some (s, _) -> s
    | None -> raise (Defect ("unregistered diagnostic code '" ^ code
                             ^ "'")) in
  let context =
    if List.mem code layer_codes && src.s_layers <> "" then
      src.s_context @ [ src.s_layers ]
    else src.s_context in
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
  let f = if d.loc.file = "" then "<input>"
    else Filename.basename d.loc.file in
  let b = Buffer.create 256 in
  Buffer.add_string b
    (Printf.sprintf "%s %s @ %s:%d:%d (%s)\n" d.severity d.code f
       d.loc.line d.loc.col d.loc.decl);
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
