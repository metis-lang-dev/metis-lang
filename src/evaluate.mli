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
