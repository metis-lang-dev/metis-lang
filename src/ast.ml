(* source position of a declaration — the DECLARED NAME's token
   (rule/link/type/pred/bwd name; a fact's or Horn rule's head
   predicate). Diagnostics only: never compiled, never keyed; the
   round-trip contract compares with locations stripped. *)
type loc = { file : string; line : int; col : int }

type term = TVar of string | TConst of string

type atom = { pred : string; terms : term list; persist : bool }

type body_elem = BAtom of atom | BDistinct of string * string

type weight =
  | WVal of float
  | WRef of { factor : string; wargs : term list; complement : bool }

type read_pattern = { ratom : atom; rguards : atom list }

type rule = {
  rname : string; rlayer : string; rdoc : string;
  rbody : body_elem list; rhead : atom list;
  rweight : weight option;
  rloc : loc }

type stage_d = { sname : string; srules : rule list }

type link_d = {
  lname : string; llayer : string; ldoc : string;
  lpre : string; lpre_atoms : atom list;
  lpost : string; lpost_atoms : atom list }

type port_kind = Weight | Guard | Input | Output

type decl =
  | DInclude of string
  | DType of string * string list
  | DNamespace of string * string list * string list option
  | DPred of string * string list * string
  | DBwd of string * string list
  | DPort of { pkind : port_kind; pname : string;
               pargs : string list;
               preads : read_pattern list option }
  | DStage of stage_d
  | DLink of link_d
  | DFact of atom
  | DHorn of atom * atom list

type catalog = {
  cname : string; cversion : int;
  cprov : (string * string * string) option;
  clayers : string list; cstages : string list;
  cextends : string option;
  cdecls : decl list;
  cdecl_locs : loc list }   (* aligned 1:1 with cdecls *)

let no_loc = { file = ""; line = 0; col = 0 }

let strip_locs (c : catalog) =
  let strip_rule r = { r with rloc = no_loc } in
  { c with
    cdecl_locs = List.map (fun _ -> no_loc) c.cdecl_locs;
    cdecls = List.map (function
        | DStage s -> DStage { s with srules = List.map strip_rule s.srules }
        | d -> d) c.cdecls }

let term_str = function TVar v -> v | TConst v -> v

let atom_str a =
  let base =
    if a.terms = [] then a.pred
    else Printf.sprintf "%s(%s)" a.pred
        (String.concat "," (List.map term_str a.terms)) in
  if a.persist then "$" ^ base else base

let weight_str = function
  | WVal v -> Printf.sprintf "@w %g" v
  | WRef { factor; wargs; complement } ->
    let args = if wargs = [] then ""
      else Printf.sprintf "(%s)"
          (String.concat "," (List.map term_str wargs)) in
    Printf.sprintf "@w %s%s%s"
      (if complement then "~" else "") factor args

let read_pattern_str p =
  if p.rguards = [] then atom_str p.ratom
  else Printf.sprintf "%s if %s" (atom_str p.ratom)
      (String.concat " * " (List.map atom_str p.rguards))

let doc_lines txt =
  if txt = "" then ""
  else String.concat ""
      (List.map (fun l -> "%% " ^ l ^ "\n")
         (String.split_on_char '\n' txt))

let atoms_str atoms = String.concat " * " (List.map atom_str atoms)

let body_str body =
  String.concat " * "
    (List.map (function
         | BAtom a -> atom_str a
         | BDistinct (a, b) -> a ^ " <> " ^ b) body)

let pretty (c : catalog) =
  let buf = Buffer.create 1024 in
  let line s = Buffer.add_string buf s; Buffer.add_char buf '\n' in
  line (Printf.sprintf "catalog %s %d." c.cname c.cversion);
  (match c.cextends with
   | Some e -> line (Printf.sprintf "extends %s." e) | None -> ());
  (match c.cprov with
   | Some (s, r, d) ->
     line (Printf.sprintf "provenance %s \"%s\" \"%s\"." s r d)
   | None -> ());
  if c.clayers <> [] then
    line (Printf.sprintf "layers (%s)." (String.concat " " c.clayers));
  if c.cstages <> [] then
    line (Printf.sprintf "stages (%s)." (String.concat " " c.cstages));
  List.iter (fun d -> match d with
      | DInclude p -> line (Printf.sprintf "include \"%s\"." p)
      | DType (n, cs) ->
        line (Printf.sprintf "type %s {%s}." n (String.concat " " cs))
      | DNamespace (n, prod, cons) ->
        let c' = match cons with
          | None -> ""
          | Some cs ->
            Printf.sprintf " consume (%s)" (String.concat " " cs) in
        line (Printf.sprintf "namespace %s produce (%s)%s." n
                (String.concat " " prod) c')
      | DPred (n, args, sp) ->
        let a = if args = [] then ""
          else Printf.sprintf "(%s)" (String.concat "," args) in
        line (Printf.sprintf "pred %s%s : %s." n a sp)
      | DBwd (n, args) ->
        let a = if args = [] then ""
          else Printf.sprintf "(%s)" (String.concat "," args) in
        line (Printf.sprintf "bwd %s%s." n a)
      | DPort { pkind; pname; pargs; preads } ->
        let k = match pkind with
          | Weight -> "weight" | Guard -> "guard"
          | Input -> "input" | Output -> "output" in
        let a = if pargs = [] then ""
          else Printf.sprintf "(%s)" (String.concat "," pargs) in
        let r = match preads with
          | None -> ""
          | Some ps ->
            Printf.sprintf " reads {%s}"
              (String.concat ", " (List.map read_pattern_str ps)) in
        line (Printf.sprintf "%s %s%s%s." k pname a r)
      | DFact a -> line (atom_str a ^ ".")
      | DHorn (h, body) ->
        line (Printf.sprintf "%s :- %s." (atom_str h)
                (String.concat ", " (List.map atom_str body)))
      | DLink l ->
        let pre = if l.lpre_atoms = [] then l.lpre
          else l.lpre ^ " * " ^ atoms_str l.lpre_atoms in
        let post = if l.lpost_atoms = [] then l.lpost
          else l.lpost ^ " * " ^ atoms_str l.lpost_atoms in
        Buffer.add_string buf (doc_lines l.ldoc);
        line (Printf.sprintf "qui %s [%s] : %s -o %s."
                l.lname l.llayer pre post)
      | DStage s ->
        line (Printf.sprintf "stage %s {" s.sname);
        List.iter (fun r ->
            let w = match r.rweight with
              | None -> "" | Some w -> "  " ^ weight_str w in
            (* the LL unit head prints as '()' (P4 sugar; the parser
               reads both spellings onto the same AST) *)
            let head = match r.rhead with
              | [{ pred = "one"; terms = []; persist = false }] -> "()"
              | hs -> atoms_str hs in
            Buffer.add_string buf (doc_lines r.rdoc);
            line (Printf.sprintf "  %s [%s] : %s -o %s%s."
                    r.rname r.rlayer (body_str r.rbody)
                    head w))
          s.srules;
        line "}")
    c.cdecls;
  Buffer.contents buf
