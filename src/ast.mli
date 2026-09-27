(* Lossless AST + canonical printer (contract: parse (pretty a) = a).
   Mirrors metis/lang/ast.py; ranges expand, comments drop, docs stay. *)

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
  rweight : weight option }

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
  cdecls : decl list }

val term_str : term -> string
val atom_str : atom -> string
val pretty : catalog -> string
