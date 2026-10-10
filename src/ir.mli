(* SPDX-License-Identifier: Apache-2.0 *)
(* The golden wire, symbolic half (01-ir-spec §6): every line except
   the trailing referee expectation of M/Z. Runs the bpn typing gate
   before writing a byte. *)

exception Ir_error of string

val case_lines :
  string                              (* case name *)
  -> Factorize.emitted
  -> Ground.program                   (* for P-line init values *)
  -> string list                      (* queries *)
  -> (string * int) list list         (* likelihood clamp sets *)
  -> string list
