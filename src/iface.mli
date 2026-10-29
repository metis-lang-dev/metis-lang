(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/15 §6 — `metisc --interface COMPOSITION.yaml`: the static
   rule×pred graph of a composition, checks I1–I12 with the cut report,
   each member's EI(S) and ei_key, the package key. *)

exception Yaml_error of string

(* the listing's lines, and the number of errors (exit 1 when > 0) *)
val run : string -> string list * int

(* the YAML subset (flow lists and maps, `key: value` lines) *)
type y = S of string | L of y list | M of (string * y) list
val read_yaml : string -> (string * y) list
val str : y -> string
val strs : y -> string list
val pairs : y -> (string * y) list

(* spec/16 amendment 1: the declarations a manifest's levels: block determines and the resolved program lacks
   (belief levels: type level, the belief's weight port, the level pred); a hand declaration that disagrees, or
   an evaluate level's missing pred, raises Compile.Lang_error naming the manifest line *)
val level_decls : string -> Ast.catalog -> Ast.decl list
val with_levels : ?manifest:string -> Ast.catalog -> Ast.catalog
val load_program : ?manifest:string -> string -> Ast.catalog
val norm : string -> string
val rel : string -> string -> string

(* a member as the check loaded it (spec/17's link reads the same) *)
type rrule = {
  r_name : string; r_file : string;
  r_body : (Ast.atom * char) list;
  r_head : Ast.atom list }
type member = {
  m_name : string; m_role : string; m_program : string; m_manifest : string;
  m_files : string list; m_includes : (string * string) list;
  m_decl_file : (string * string) list; m_sigs : (string * string list) list;
  m_bwd : string list; m_types : (string * string list) list; m_abstract : string list;
  m_rules : rrule list; m_init : (string * int) list; m_facts : Ast.atom list;
  m_shared : (string * string) list; m_status : (string * string list) list;
  m_extra : (string * y) list; m_key : string; m_compile : string option;
  m_inc : (string * string * string) list; m_inc_err : string list }
type ipkg = { i_path : string; i_name : string; i_key : string;
              i_preds : string list; i_rules : bool;
              i_nature : (string * string) list option }
type finding = { sev : string; chk : string; text : string }
val load_member : string -> string -> string -> member

(* the whole check, for the link (spec/17 §4.2: I1-I12 are L1-L12) *)
type analysis = {
  a_path : string; a_dir : string; a_comp : (string * y) list;
  a_specialists : string list; a_direct : string;
  a_world_out : string list; a_world_in : string list;
  a_capacity : string; a_cap_key : string; a_ipkgs : ipkg list;
  a_members : member list; a_findings : finding list;
  a_canon : string; a_package_key : string; a_lines : string list; a_errors : int }
(* ?direct_dir: where the direct member's package is (the link's generated director) *)
val analyse : ?direct_dir:string -> string -> analysis

(* the instrument's reader of the YAML subset with block mappings (spec/16 §5) *)
val read_yaml_block : string -> (string * y) list
