(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/17 §4 — `metisc --link composition.yaml [-o DIR] [--check] [--tar]
   [--bundles DIR]`: the composition's checks (I1–I12 as L1–L12, then
   L13–L25), the DERIVED direct member (§3.3), every member's wire, and the
   image (image.json, image.lock, members/<m>/, tools.json) under one hash. *)

type opts = {
  out : string option;        (* -o: the build directory (default: <composition dir>/build) *)
  check : bool;               (* --check: the checks and the hash, nothing written *)
  tar : bool;                 (* --tar: also <image>.tar, the same files *)
  bundles : string option;    (* --bundles DIR: DIR/<member>/{sidecar.json,tools.json}, copied and key-checked (L19);
                                 transitional (the image is OCaml-only: step 3 decides whether metisc emits the sidecar) *)
  build : bool;               (* `metisc build` (§7): reuse the last image's wire of every member whose source key is
                                 unchanged (OUT/<name>.build), compile the stale ones, link, record *)
}

(* WIRE: a program's path -> its wire lines and its program key (metisc
   --wire's compile, main.ml's). → the listing's lines, the error count. *)
val run : wire:(string -> string list * string) -> opts -> string -> string list * int
