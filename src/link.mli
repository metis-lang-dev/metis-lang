(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/17 §4 — `metisc --link composition.yaml [-o DIR] [--check] [--tar]
   [--plan FILE] | metisc build | metisc check`: the composition's checks (I1–I12 as L1–L12, then
   L13–L25), the DERIVED direct member (§3.3), every member's wire, and the
   image (image.json, image.lock, members/<m>/, tools.json) under one hash. *)

type opts = {
  out : string option;        (* -o: the build directory (default: <composition dir>/build) *)
  check : bool;               (* --check: the checks and the hash, nothing written *)
  tar : bool;                 (* --tar: also <image>.tar, the same files *)
  build : bool;               (* `metisc build` (§7): reuse the last image's wire of every member whose source key is
                                 unchanged (OUT/<name>.build), compile the stale ones, link, record *)
  plans : string list;        (* --plan FILE (repeatable): a deployment plan (§5), its table written to plans/<p>.json *)
}

(* WIRE: a program's path -> its wire lines, its program key and its sidecar.json (metisc
   --wire's compile and the emitter, main.ml's). → the listing's lines, the error count. *)
val run : wire:(string -> string list * string * string) -> opts -> string -> string list * int

(* spec/17 §2: a lone package's one-member image (`metisc --link PKGDIR [--serve FILE] [--extension E]...`). BUNDLE:
   a served file and its extensions -> the wire lines, the program key, the sidecar. *)
val run_package : bundle:(string -> string list -> string list * string * string) -> opts -> ?serve:string
  -> ?extensions:string list -> string -> string list * int
