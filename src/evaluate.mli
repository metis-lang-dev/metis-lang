(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/16 §6 — the one-tick instrument: P(outcome within h) over
   worlds × traces, the belief groups drawn from their ports, the rule
   weights and port factors frozen for the tick, exact rationals, the
   state budget cutting to [lo, hi]. `brute` is the referee (§7): every
   world up front, every path, no merging, no absorption shortcut, no
   budget. *)

exception Refused of string * string     (* code, text: exit 2 *)

type result = {
  lines : string list;                   (* V, L, N lines (stdout) *)
  costs : string list;                   (* C lines (stderr, --cost) *)
  mismatches : int }                     (* `expect` failures: exit 1 *)

(* the resolved source (signatures), the compiled catalog and ports,
   the program grounded on the case's init, the init itself, and the
   case's instrument directives as token lists (belief, port,
   evaluate, expect, level) *)
val run : Ast.catalog -> Catalog.t -> Compile.ports -> Ground.program
  -> init:(string * int) list -> string list list -> brute:bool -> result

(* a case YAML and its manifest (spec/16 §5, §7), read into the
   program's path, the init and the SAME directives the embedded form
   gives: the manifest's beliefs:, levels: and evaluate:, the case's
   init:, ports: (a number, or a table atom -> number), evaluate: and
   expect:. The manifest is the case's `manifest:`, else domain.yaml in
   the parent of a `cases/` directory, else beside the case. *)
val case_of_yaml : string -> string * (string * int) list * string list list
