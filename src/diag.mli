(* Structured diagnostics — findings as certified slices (spec 08 D0).
   Byte-identical with metispy metis/kernel/diagnostics.py: the same
   registry, constructor rules, text and JSON renderings. Depends on
   nothing, so the kernel (Catalog) and the compiler both emit. *)

type loc = { file : string; line : int; col : int; decl : string }

(* a declaration's precomputed slice (built by the compiler, threaded
   through Catalog.entry so kernel checks far from the AST copy it) *)
type src = {
  s_loc : loc;
  s_subject : string list;
  s_context : string list;   (* preds -> namespaces -> types *)
  s_layers : string }        (* the `layers (...)` line, or "" *)

type t = {
  code : string; severity : string; loc : loc;
  subject : string list; context : string list;
  data : (string * string) list; hint : string; text : string }

exception Defect of string
(* unknown code / context over the cap: an emitter bug, never silent *)

val context_cap : int
val registry : (string * (string * bool)) list
(* code -> (severity, migrated); `migrated` is step-1 scaffolding *)

val no_src : src
val make : string -> string -> src -> (string * string) list -> t
(* make code text src data — the ONE constructor *)

(* the emission sink: Compile.compile resets it; the compiler and the
   kernel checks push; Compile.diagnostics () reads it *)
val reset : unit -> unit
val emit : t -> unit
val collected : unit -> t list

val render_text : t -> string
val to_json : t -> string
