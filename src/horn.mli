(* SLD backward chaining over the closed Horn world (01-ir-spec §1).
   Query variables are "?name"; enumeration order is normative:
   clause declaration order, depth-first, deduplicated first-wins.
   Depth bound 256. *)

type pattern = string * string list

type clause = { head : pattern; body : pattern list;
                vars : string list }

type db

val make : clause list -> db
val derivable : db -> pattern -> bool

(* bindings of the sorted ?-vars of the goal conjunction (keys sans
   '?'), SLD order, deduped on the bound-value tuple *)
val solutions : db -> pattern list -> (string * string) list list
