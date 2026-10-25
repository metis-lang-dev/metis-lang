(* SPDX-License-Identifier: Apache-2.0 *)
(* Exact non-negative rationals over a stdlib-only arbitrary-precision
   natural (base 2^24 limbs) — spec/16 §6.4: the instrument's value is
   a rational, so the brute-force referee agrees to the last digit. *)

type t

exception Negative of string     (* a subtraction below zero *)

val zero : t
val one : t
val of_int : int -> t
val add : t -> t -> t
val sub : t -> t -> t            (* a - b, raises Negative when b > a *)
val mul : t -> t -> t
val div : t -> t -> t            (* b > 0 *)
val compare : t -> t -> int
val is_zero : t -> bool

(* a decimal literal, exactly: "0.7" = 7/10, "1e-05", "2.59459e+08";
   None for anything else (a sign, inf, nan) *)
val of_decimal : string -> t option

(* a binary64 as the exact decimal of its shortest round-trip
   representation (spec/16 §6.4): 0.7 -> 7/10 *)
val of_float : float -> t option

val to_string : t -> string      (* "p/q", reduced, q >= 1 *)
val to_float : t -> float        (* correctly rounded (normal range) *)
val den_bits : t -> int          (* the denominator's size in bits *)
val den_digits : t -> int        (* … in decimal digits *)
