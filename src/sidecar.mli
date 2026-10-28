(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/17 ruling 6 (linker s-5908724a step 5c): a member's sidecar.json, emitted by metisc byte-equal to metispy's
   artifact.sidecar (metis-sidecar/1): the events in wire order with their canonical index, rule, doc words and
   target; the cards offerable at the served node (served, sibling, extension); the script (each card's clauses
   and atoms); the case's init, steps and queries. Rulings: a card's error is a diagnostic code, never exception
   text; atoms in the wire's canonical form; slots and lines from the parsed AST; the layout of python's
   json.dumps(indent=1, ensure_ascii=False). *)

type py = PS of string | PI of int | PB of bool | PN | PL of py list | PO of (string * py) list

(* python's json.dumps(v, indent=1, ensure_ascii=False), without the trailing newline *)
val py_json : py -> string

(* the sidecar's text (with its final newline). program: the served file; extensions: the files merged into it;
   cat / prog: its compiled catalog and ground program; init / steps / queries: its # case *)
val emit : program:string -> extensions:string list -> cat:Catalog.t -> prog:Ground.program
  -> init:(string * int) list -> steps:int -> queries:string list -> string
