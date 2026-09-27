(* Bayesian-proof-net typing gate over the emitted net (paper Prop 6;
   EFD Defs 3.1+3.2, Lemma 3.1). Structural pass only — box rule,
   SSA single-writer, no dangling premise, polarized acyclicity.
   Runs before serialization: no ill-typed artifact ships. *)

exception Bpn_error of string

val check : Factorize.emitted -> unit
