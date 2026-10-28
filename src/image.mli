(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/17 §3 — the image's files: image.json (a small JSON writer, keys in
   the order given, so the bytes are canonical), the canonical file-list
   hash, and the directory written or archived (ustar, stdlib only). *)

type j = JS of string | JI of int | JB of bool | JN | JL of j list | JO of (string * j) list

(* the JSON text, two-space indented, keys in the order given *)
val to_string : j -> string

(* the image hash (§9.1): sha256 over "PATH SHA256\n" for each file in the
   canonical order given; the first twelve hex digits name the image *)
val hash : (string * string) list -> string

val read_file : string -> string
val write_file : string -> string -> unit
val mkdir_p : string -> unit

(* a ustar archive of FILES (path in the archive, content), in order *)
val tar : (string * string) list -> string
