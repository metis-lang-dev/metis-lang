(* SPDX-License-Identifier: Apache-2.0 *)
(* The linter (spec/08 lint phase, patterns CHECKS.md §3): shape
   findings over a program that COMPILES, never gating — the mirror of
   metispy metis/lint.py, byte for byte through Diag.render_text.
   `metisc --lint FILE.llp [--manifest domain.yaml] [--strict]`. *)

(* the lint findings of a compiled program: its resolved AST (the
   compiler's input), the compiled catalog, the file's TEXT (for its
   `#init` lines), its manifest (domain.yaml) and its path (for
   stages-twice across its includes) — in metispy's order: state-dead-end
   / state-unproduced per pred in declaration order, rules-twin-body per
   stage in rule order, report-ungated in rule order, stages-twice *)
val lint : Ast.catalog -> Catalog.t -> text:string -> ?manifest:string ->
  ?path:string -> unit -> Diag.t list

(* `#init ATOM [N]` lines as counts (the last assignment wins) *)
val init_counts : string -> (string * int) list

(* the init half of each `invariant`: the counts must hold exactly the
   declared sum over the members (all ground atoms of each member pred) *)
val invariant_init : Catalog.t -> (string * int) list -> Diag.t list
