(* SPDX-License-Identifier: Apache-2.0 *)
(* The portable reference sampler (06-sampler-wire.md): splitmix64 +
   canonical event order + normative selection arithmetic — the
   evaluator ladder's bottom rung, FULL language (no class-F
   restriction), byte-identical traces across Python/OCaml/C++. *)

val sm_unit : int64 ref -> float          (* splitmix64 unit draw *)

type event_row = { kind : [`Clause | `Link]; stage : string;
                   ev : Ground.event }

val canonical_events : Ground.program -> event_row array

val run_trace : Ground.program -> int -> int
  -> int list * (string * (string * int) list)
(* prog steps seed -> (canonical event indices,
   (final stage or "(done)", final multiset)) *)

val run_trace_pick : Ground.program -> int -> int
  -> pick:(string -> (int * float) list -> float -> int option)
  -> int list * (string * (string * int) list)
(* run_trace with an external-choice hook ('#interactive' stages,
   the additive &): pick stage candidates total = Some i resolves
   the CHOICE externally (no randomness consumed); None falls
   through to the reference sampler draw. run_trace is
   run_trace_pick with the constant-None pick. *)

val final_line : int -> string * (string * int) list -> string
