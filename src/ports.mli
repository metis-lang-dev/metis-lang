(* SPDX-License-Identifier: Apache-2.0 *)
(* Ground read-scopes + the symbolic hook table (01-ir-spec §3).
   The binding CLOSURE stays native/referee-side; the compiler needs
   only the symbolic data: factor, ground args, scope, complement.
   Scope ORDER is normative — it reaches the wire (K-line varats). *)

type hook = {
  hk_factor : string;
  hk_args : string list;
  hk_scope : string list;       (* ground atoms, declared order *)
  hk_compl : bool }

(* factorability admission: every referenced weight port must declare
   `reads` — else Lang_error, same rule as python factor_hooks *)
val hooks : Ground.program -> Compile.ports -> Catalog.t
  -> (string * hook) list      (* event name -> hook *)

val ground_reads : Compile.ports -> string -> string list -> Horn.db
  -> string list

(* the catalog's Horn database (the guards' facts and rules) *)
val horn_db : Catalog.t -> Horn.db

(* a ground event name's rule ("go_for[O=t,R=p0]" -> "go_for") and its
   tag substitution ([O, t; R, p0]) *)
val base_name : string -> string
val tag_subst : string -> (string * string) list
