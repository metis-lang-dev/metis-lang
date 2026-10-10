(* SPDX-License-Identifier: Apache-2.0 *)
(* Min-fill elimination replay (01-ir-spec §5): width, factor-ops,
   ORDER (the shipped schedule). The (fill, name) lexicographic
   tie-break is normative — the schedule must be byte-identical
   across implementations and processes. *)

val elim_cost :
  string list list                 (* emitted scopes *)
  -> (string * int) list           (* cardinalities (default 2) *)
  -> string list                   (* keep (query vars) *)
  -> int * int * string list       (* width, ops, order *)
