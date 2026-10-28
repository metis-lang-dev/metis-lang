(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/17 ruling 6: a member's sidecar.json, byte-equal to metispy's artifact.sidecar. See sidecar.mli. The
   comments name the python each part mirrors (metispy metis/kernel/artifact.py, metis/loop/cards.py). *)

open Ast

type py = PS of string | PI of int | PB of bool | PN | PL of py list | PO of (string * py) list

(* json.dumps(indent=1, ensure_ascii=False): python escapes the quote, the backslash and the control characters
   (\n \r \t \b \f by name, the rest as \u00XX), and leaves every other byte as it is *)
let esc s =
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
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

let py_json v =
  let b = Buffer.create 65536 in
  let rec go ind = function
    | PS s -> Buffer.add_string b (esc s)
    | PI n -> Buffer.add_string b (string_of_int n)
    | PB x -> Buffer.add_string b (if x then "true" else "false")
    | PN -> Buffer.add_string b "null"
    | PL [] -> Buffer.add_string b "[]"
    | PO [] -> Buffer.add_string b "{}"
    | PL l ->
      Buffer.add_string b "[\n";
      List.iteri (fun i x ->
          if i > 0 then Buffer.add_string b ",\n";
          Buffer.add_string b (String.make (ind + 1) ' '); go (ind + 1) x) l;
      Buffer.add_string b ("\n" ^ String.make ind ' ' ^ "]")
    | PO m ->
      Buffer.add_string b "{\n";
      List.iteri (fun i (k, x) ->
          if i > 0 then Buffer.add_string b ",\n";
          Buffer.add_string b (String.make (ind + 1) ' ' ^ esc k ^ ": "); go (ind + 1) x) m;
      Buffer.add_string b ("\n" ^ String.make ind ' ' ^ "}") in
  go 0 v;
  Buffer.contents b

let ps_opt = function Some s -> PS s | None -> PN
let mset m = PO (List.map (fun (a, n) -> (a, PI n)) m)

(* cards._words: a %% doc as its words, with its `target: <catalog>` tags *)
let words doc =
  let tags = ref [] and text = ref [] in
  List.iter (fun ln ->
      let l = String.trim ln in
      match String.index_opt l ':' with
      | Some i when String.sub l 0 i = "target"
                    && (let r = String.trim (String.sub l (i + 1) (String.length l - i - 1)) in
                        r <> "" && String.for_all (fun c -> c = '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                                                            || (c >= '0' && c <= '9')) r) ->
        tags := ("target", String.trim (String.sub l (i + 1) (String.length l - i - 1))) :: !tags
      | _ -> if l <> "" then text := l :: !text) (String.split_on_char '\n' doc);
  (String.concat " " (List.rev !text), List.rev !tags)

let resolved f = Compile.resolve_includes (Parser.parse_file f) (Filename.dirname f)

(* artifact.rule_lines: rule name -> its words and tags, over the files with their includes spliced *)
let rule_lines files =
  let tbl = Hashtbl.create 64 in
  List.iter (fun f ->
      List.iter (function
          | DStage s -> List.iter (fun r -> Hashtbl.replace tbl r.rname (words r.rdoc)) s.srules
          | _ -> ()) (resolved f).cdecls) files;
  tbl

let rule_of name = match String.index_from_opt name 0 '[', String.index_from_opt name 0 '(' with
  | Some i, Some j -> String.sub name 0 (min i j)
  | Some i, None | None, Some i -> String.sub name 0 i
  | None, None -> name

(* cards._scan, from the parsed AST (ruled: slots from the declarations, never a regex over the text) *)
type scan = { s_name : string; s_file : string; s_text : string option; s_extends : string option;
              s_includes : string list; s_types : string list }

let norm p = Iface.norm p

let scan f =
  match Parser.parse_file f with
  | exception _ -> None
  | c ->
    let dir = Filename.dirname f in
    Some { s_name = c.cname; s_file = norm f;
           s_text = (match c.cprov with Some ("text", t, _) -> Some t | _ -> None);
           s_extends = c.cextends;
           s_includes = List.filter_map (function DInclude i -> Some (norm (Filename.concat dir i)) | _ -> None) c.cdecls;
           s_types = List.filter_map (function DType (t, _) -> Some t | _ -> None) c.cdecls }

(* a card's error: a diagnostic code (ruled), the compiler's when it has one *)
let error_code e =
  match Compile.diagnostics () with
  | d :: _ -> d.Diag.code
  | [] -> (match e with Compile.Lang_error _ -> "compile" | Catalog.Catalog_error _ -> "catalog" | _ -> "card-ground")

(* cards._side: one side's atoms by name, multiplicity folded, in order ($-premises kept: needed, not consumed) *)
let side atoms =
  let out = ref [] in
  List.iter (fun (a : atom) ->
      if a.pred <> "one" then begin
        let s = atom_str a in
        let s = if String.length s > 0 && s.[0] = '$' then String.sub s 1 (String.length s - 1) else s in
        match List.find_opt (fun (k, p, _) -> k = s && p = a.persist) !out with
        | Some (_, _, n) -> incr n
        | None -> out := !out @ [(s, a.persist, ref 1)]
      end) atoms;
  PL (List.map (fun (s, p, n) -> PO [("atom", PS s); ("n", PI !n); ("kept", PB p)]) !out)

let side_atoms = function
  | PL l -> List.filter_map (function PO kv -> (match List.assoc_opt "atom" kv with Some (PS s) -> Some s | _ -> None)
                                    | _ -> None) l
  | _ -> []

(* cards.script_of: one card's clauses and atoms; a sibling or an extension lists only what its moves use *)
let script_of ~name ~file ~relation ~text ~moves =
  let c = resolved file in
  (* a pred's doc: its %% lines, as metispy's take_docs gives them (Parser.pred_doc: kept beside the AST) *)
  let preds = List.filter_map (function DPred (n, _, _) -> Some (n, Parser.pred_doc n) | _ -> None) c.cdecls in
  let clauses = List.concat_map (function
      | DStage st -> List.filter_map (fun r ->
          if relation <> "served" && not (List.exists (fun m ->
              m = r.rname || (String.length m > String.length r.rname
                              && String.sub m 0 (String.length r.rname + 1) = r.rname ^ "(")) moves)
          then None
          else
            let (w, tags) = words r.rdoc in
            let body = List.filter_map (function BAtom a -> Some a | BDistinct _ -> None) r.rbody in
            Some (r.rname, w, [("name", PS r.rname); ("stage", PS st.sname); ("doc", PS w);
                               ("premises", side body); ("effects", side r.rhead);
                               ("target", ps_opt (List.assoc_opt "target" tags))])) st.srules
      | _ -> []) c.cdecls in
  let preds = if relation = "served" then preds else
      let used = List.concat_map (fun (_, _, kv) ->
          List.map (fun s -> match String.index_opt s '(' with Some i -> String.sub s 0 i | None -> s)
            (side_atoms (List.assoc "premises" kv) @ side_atoms (List.assoc "effects" kv))) clauses in
      List.filter (fun (n, _) -> List.mem n used) preds in
  (name, relation, text, clauses, preds)

let script_json (name, relation, text, clauses, preds) extra_missing =
  PO [("name", PS name); ("relation", PS relation); ("text", ps_opt text);
      ("clauses", PL (List.map (fun (_, _, kv) -> PO kv) clauses));
      ("atoms", PL (List.map (fun (n, d) -> PO [("name", PS n); ("doc", PS d)]) preds));
      ("missing", PO [("clause_doc", PL (List.map (fun n -> PS n)
                                          (List.filter_map (fun (n, w, _) -> if w = "" then Some n else None) clauses
                                           @ extra_missing)));
                      ("atom_doc", PL (List.filter_map (fun (n, d) -> if d = "" then Some (PS n) else None) preds))])]

let emit ~program ~extensions ~cat ~prog ~init ~steps ~queries =
  let lines = rule_lines (program :: extensions) in
  let canon_tbl = Refsample.canonical_events prog in
  let canon_of ev =
    let r = ref (-1) in
    Array.iteri (fun j (row : Refsample.event_row) -> if !r < 0 && row.ev == ev then r := j) canon_tbl;
    if !r < 0 then Array.iteri (fun j (row : Refsample.event_row) ->
        if !r < 0 && row.ev.Ground.ev_name = ev.Ground.ev_name then r := j) canon_tbl;
    !r in
  let rows = List.concat_map (fun (s, evs) -> List.map (fun ev -> ("clause", s, ev)) evs) prog.Ground.stages
             @ List.map (fun (ev : Ground.event) -> ("link", Option.value ev.ev_pre ~default:"", ev)) prog.Ground.links in
  let events = List.mapi (fun i (kind, stage, (ev : Ground.event)) ->
      let rule = rule_of ev.ev_name in
      let (w, tags) = match Hashtbl.find_opt lines rule with Some x -> x | None -> ("", []) in
      PO ([("i", PI i); ("canon", PI (canon_of ev)); ("name", PS ev.ev_name); ("rule", PS rule);
           ("kind", PS kind); ("stage", PS stage); ("line", PS w)]
          @ (match List.assoc_opt "target" tags with Some t -> [("target", PS t)] | None -> []))) rows in
  (* the cards (cards.cards): the served one, then each catalog beside it that extends it or shares an include *)
  let served = scan program in
  let cname = cat.Catalog.k_name in      (* the served catalog's: an extension merged in is plant+visitor (admit) *)
  let own = List.map (fun (_, _, (ev : Ground.event)) -> ev.ev_name) rows in
  let cards = match served with
    | None -> []
    | Some sv ->
      let others = List.sort compare (List.filter (fun f -> Filename.check_suffix f ".llp")
                                        (Array.to_list (Sys.readdir (Filename.dirname sv.s_file)))) in
      (cname, sv.s_file, sv.s_text, "served", sv.s_types, Some ([], [])) ::
      List.filter_map (fun f ->
          match scan (Filename.concat (Filename.dirname sv.s_file) f) with
          | None -> None
          | Some c when c.s_file = sv.s_file || c.s_text = None -> None
          | Some c ->
            let rel = if c.s_extends = Some cname then Some "extends"
              else if List.exists (fun i -> List.mem i sv.s_includes) c.s_includes then Some "sibling" else None in
            Option.map (fun rel ->
                let mv = try
                    let p = match rel with
                      | "extends" ->
                        let base_ast = resolved program in
                        let (ecat, _) = Compile.compile ~base:(cat, base_ast) (resolved c.s_file) in
                        Ground.ground (Catalog.admit cat ecat) init
                      | _ -> let (scat, _) = Compile.compile (resolved c.s_file) in Ground.ground scat init in
                    let evs = ref [] in
                    List.iter (fun (ev : Ground.event) ->
                        if not (List.mem ev.ev_name own) && not (List.mem_assoc ev.ev_name !evs) then
                          evs := !evs @ [(ev.ev_name, ev)]) (Ground.events p);
                    let names = List.sort compare (List.map fst !evs) in
                    Ok (names, List.map (fun n -> let ev = List.assoc n !evs in
                                          PO [("name", PS n); ("consume", mset ev.Ground.ev_consume);
                                              ("produce", mset ev.ev_produce); ("persist", mset ev.ev_persist)]) names)
                  with e -> Error (error_code e) in
                (c.s_name, c.s_file, c.s_text, rel, c.s_types,
                 match mv with Ok (n, e) -> Some (n, e) | Error code -> (ignore code; None))) rel
            |> Option.map (fun x -> x)) others
      |> List.map (fun x -> x) in
  let card_err = Hashtbl.create 4 in
  let card_json (name, _, text, rel, slots, mv) =
    let base = [("name", PS name); ("text", ps_opt text); ("relation", PS rel)] in
    if rel = "served" then PO (base @ [("moves", PL []); ("effects", PL []); ("slots", PL (List.map (fun s -> PS s) slots))])
    else match mv with
      | Some (names, effs) ->
        PO (base @ [("slots", PL (List.map (fun s -> PS s) slots)); ("moves", PL (List.map (fun s -> PS s) names));
                    ("effects", PL effs)])
      | None ->
        let code = Option.value (Hashtbl.find_opt card_err name) ~default:"card-ground" in
        PO (base @ [("slots", PL (List.map (fun s -> PS s) slots)); ("moves", PL []); ("effects", PL []);
                    ("error", PS code)]) in
  let script = List.map (fun (name, file, text, rel, _, mv) ->
      let moves = match mv with Some (n, _) -> n | None -> [] in
      try
        let s = script_of ~name ~file ~relation:rel ~text ~moves in
        if rel = "served" && extensions <> [] then begin
          let (n, r, t, cl, pr) = s in
          let ext = List.concat_map (fun p ->
              let (_, _, _, ecl, _) = script_of ~name ~file:p ~relation:"served" ~text:None ~moves:[] in
              List.map (fun (cn, w, kv) -> (cn, w, kv @ [("extension", PS (Filename.basename p))])) ecl) extensions in
          script_json (n, r, t, cl @ ext, pr) []
        end else script_json s []
      with e -> PO [("name", PS name); ("relation", PS rel); ("text", ps_opt text); ("clauses", PL []);
                    ("atoms", PL []); ("error", PS (error_code e))]) cards in
  let side = PO [
      ("format", PS "metis-sidecar/1"); ("catalog", PS cname); ("key", PS (Nets.program_key prog));
      ("extensions", PL (List.map (fun p -> PS (Filename.basename p)) extensions));
      ("init", PO (List.fold_left (fun acc (a, n) ->
           if List.mem_assoc a acc then List.map (fun (k, v) -> if k = a then (k, PI n) else (k, v)) acc
           else acc @ [(a, PI n)]) [] init));
      ("steps", PI steps);
      ("stages", PL (List.map (fun (s, _) -> PS s) prog.Ground.stages));
      ("events", PL events);
      ("cards", PL (List.map card_json cards));
      ("queries", PL (List.map (fun q -> PS q) queries));
      ("script", PL script);
      ("ir", PN)] in
  py_json side ^ "\n"
