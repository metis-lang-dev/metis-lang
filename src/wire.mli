(* SPDX-License-Identifier: Apache-2.0 *)
(* The product ground wire (bundle-compiler step 1): what a domain
   package's bundle serves to the C++ runtime (runtime/include/metis/
   loader.hpp). The corpus wire's N/E/I/S grammar PLUS the B port
   manifest (in|out|guard|weight — what the consuming registry must
   bind) and each priced event's `; w factor compl args` section, MINUS
   the Q/D/R expectations. Byte-equal to metispy's
   metis.kernel.wire.emit_artifact. *)

(* an extension's ports over its base's (metispy merge_ports): the
   extension's entries override, inputs/outputs append the new ones *)
val merge_ports : Compile.ports -> Compile.ports -> Compile.ports

(* a weight as the wire carries it: the shortest text that reads back
   as the same double (python repr), an integral value without ".0" *)
val weight_text : float -> string

(* the artifact's lines: header comment, N, B manifest, E per event
   (Ground.events order), I (atoms sorted), S *)
val artifact_lines :
  Catalog.t -> Compile.ports -> Ground.program -> int -> string list
