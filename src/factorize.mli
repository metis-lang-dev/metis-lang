(* SPDX-License-Identifier: Apache-2.0 *)
(* The symbolic factored emission (01-ir-spec §4): constant folding,
   CHOICE sites, SSA writes, double-production guards, stall
   analysis. NO tables, NO binding calls — this is the admission/
   compilation half only; evaluation stays referee-side (Python). *)

exception Factorize_error of string

type env_v = Cst of int | Var of string

type hook_ser = {
  hs_factor : string; hs_args : string list; hs_compl : bool;
  hs_base : string list;                (* scope atoms at 1, sorted *)
  hs_varats : (string * string) list }  (* scope order: atom, var *)

type rec_ = {
  r_name : string; r_weight : float;
  r_deps : string list;                 (* parent vars needed at 1 *)
  r_hook : hook_ser option }

type site = {
  s_var : string; s_card : int;
  s_parents : string list;              (* first-seen order *)
  s_recs : rec_ list }                  (* CPT row order *)

type write = {
  w_x : string; w_card : int; w_new : string;
  w_old : string option;
  w_vals : int option list }            (* None = keep *)

type emitted = {
  e_cards : (string * int) list;        (* mint order *)
  e_sites : site list;
  e_writes : write list;
  e_guards : ((string * int * string) * int list) list;
  e_unknown_vars : (string * string) list;   (* atom -> var, sorted *)
  e_env : (string, env_v) Hashtbl.t;    (* final environment *)
  e_maybe_stall : bool }

val emit : Ground.program -> int -> (string -> Ports.hook option)
  -> string list -> emitted

(* the emitted factor scopes — certificate, jtree and wire all read
   this one description *)
val structure : emitted -> string list list
