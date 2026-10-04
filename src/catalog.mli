(* Kernel catalog types + containment typecheck (00-language-spec §6).
   Mirrors metis/kernel/{schema,catalog,typing}.py. All assoc lists
   are INSERTION-ORDERED — order is semantic (01-ir-spec §0). *)

type pattern = string * string list

type clause_schema = {
  cs_name : string; cs_stage : string;
  cs_vars : (string * string) list;          (* var -> type, ordered *)
  cs_consume : pattern list; cs_produce : pattern list;
  cs_persist : pattern list; cs_guards : pattern list;
  cs_distinct : (string * string) list;
  cs_weight : float }

type link_schema = {
  ls_name : string; ls_pre : string; ls_post : string;
  ls_vars : (string * string) list;
  ls_consume : pattern list; ls_produce : pattern list;
  ls_persist : pattern list; ls_guards : pattern list;
  ls_distinct : (string * string) list }

type horn_clause = {
  h_head : pattern; h_body : pattern list; h_vars : string list }

type payload =
  | PSchema of clause_schema
  | PLink of link_schema
  | PHorn of horn_clause

type entry = {
  e_name : string; e_layer : string; e_comment : string;
  e_payload : payload;
  e_src : Diag.src }   (* the decl's diagnostic slice (spec 08) *)

type t = {
  k_name : string; k_version : int;
  k_layers : string list; k_stages : string list;
  k_types : (string * string list) list;     (* declaration order *)
  k_namespaces : (string * (string list * string list)) list;
  k_preds : (string * string) list;          (* pred -> namespace *)
  k_bwd : string list;
  k_entries : entry list;
  k_srcs : (string * Diag.src) list }
  (* decl slices for catalog-level / admission diagnostics (spec 08),
     keyed "pred/x", "bwd/x", "namespace/y", "type/t" *)

val typecheck : t -> string list             (* findings; [] = OK *)

exception Catalog_error of string list

(* containment by construction: a pack may only ADD — new types,
   namespaces, preds in ITS OWN namespaces, bwd, entries; never
   redeclare or extend, never claim a base namespace, never add a
   stage. Merged catalog is re-typechecked. *)
val admit : t -> t -> t
