(* SPDX-License-Identifier: Apache-2.0 *)
(* Canonical identity — the neutral serialization
   (docs/rewrite/03-canonical-key.md). canonical_string must be
   byte-identical to python's kernel/nets.canonical_bytes for every
   program; program_key = SHA-256 of it. This is what lets a second
   toolchain share the artifact cache. *)

(* the canonical event/link lines — also the sampler's normative
   event ORDER key (06-sampler-wire §2) *)
val clause_line : Ground.event -> string
val link_line : Ground.event -> string

val canonical_string : Ground.program -> string
val program_key : Ground.program -> string
