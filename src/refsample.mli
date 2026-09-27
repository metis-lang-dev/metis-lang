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

val final_line : int -> string * (string * int) list -> string
