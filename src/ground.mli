(* Π-grounding (01-ir-spec §2). Order is normative: substitutions
   enumerate the schema's var table (first-occurrence order) with the
   LAST var fastest, each var over its type's constants in declaration
   order; multisets accumulate first-occurrence-ordered. *)

type mset = (string * int) list              (* ordered, counts > 0 *)

type event = {
  ev_name : string;                          (* schema[X=c,Y=d] *)
  ev_consume : mset; ev_produce : mset; ev_persist : mset;
  ev_weight : float;
  ev_pre : string option;                    (* links only *)
  ev_post : string option }

type program = {
  stages : (string * event list) list;       (* declared stage order *)
  links : event list;
  init_stage : string;
  init : mset }

val ground : Catalog.t -> (string * int) list -> program

(* stable event table: clauses in stage order, then links *)
val events : program -> event list
