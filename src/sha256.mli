(* SHA-256 (FIPS 180-4), pure stdlib — the OCaml stdlib Digest is
   MD5-only and canonical identity deserves a collision-resistant
   hash. Pinned against hashlib via the corpus keys gate and the
   standard vectors ("" and "abc") in the driver selftest. *)

val hex : string -> string
