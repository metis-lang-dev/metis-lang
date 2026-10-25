(* SPDX-License-Identifier: Apache-2.0 *)
(* AST -> kernel catalog + ports (00-language-spec §5). Findings
   accumulate; Lang_error carries them all.

   Includes: resolve_includes splices included files' decls in place
   (recursive, cycles rejected); layers/stages ADOPTED when the
   includer omits them (the RDDL-style domain/instance split).

   Packs: `extends` requires ?base = (compiled base catalog, its
   SOURCE ast — signatures for inference come from the source);
   layers/stages inherit when omitted; typechecking is DEFERRED to
   admission (Catalog.admit). *)

exception Lang_error of string list

type weight_ref = {
  w_factor : string;
  w_args : string list;        (* constants or schema var names *)
  w_compl : bool }

type ports = {
  p_weights : (string * string list) list;   (* factor -> formals *)
  p_reads : (string * Ast.read_pattern list) list;  (* the contract *)
  p_weight_refs : (string * weight_ref) list;       (* rule -> ref *)
  (* declared only (the product wire's B manifest, metispy Ports):
     guard -> formals (a redeclaration replaces), inputs and outputs in
     declaration order *)
  p_guards : (string * string list) list;
  p_inputs : string list;
  p_outputs : string list }

val resolve_includes : Ast.catalog -> string -> Ast.catalog

(* an include's file: the including file's directory, the catalog root
   ($METIS_CATALOG, else the cwd), $METIS_HOME — the first that holds
   it; a miss raises Lang_error naming the three. include_place also
   returns the place's tag: dir | root | home *)
val include_place : string -> string -> string * string
val include_path : string -> string -> string

(* a source's includes, transitively, first-seen: (string, place, file) *)
val include_list : Ast.catalog -> string -> (string * string * string) list

val compile : ?base:(Catalog.t * Ast.catalog) -> Ast.catalog
  -> Catalog.t * ports

(* advisory warnings of the LAST compile (never gating; e.g. a
   singleton var in a Horn fact) *)
val warnings : unit -> string list

(* structured diagnostics (spec 08) of the LAST compile, plus those of
   a Catalog.admit run right after it; a failing compile leaves its
   error diagnostics here beside the Lang_error strings *)
val diagnostics : unit -> Diag.t list
