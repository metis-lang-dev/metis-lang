(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/15 §6 — `metisc --interface COMPOSITION.yaml`: the static
   rule×pred graph of a composition, checks I1–I12 with the cut report,
   each member's EI(S) and ei_key, the package key. *)

exception Yaml_error of string

(* the listing's lines, and the number of errors (exit 1 when > 0) *)
val run : string -> string list * int
