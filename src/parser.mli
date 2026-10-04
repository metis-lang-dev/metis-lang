(* Recursive-descent parser (00-language-spec §2). Docs attach to the
   next rule/link; range sugar expands in the AST. *)

exception Parse_error of string

val parse : ?file:string -> string -> Ast.catalog
(* ?file names the source in every decl location (default "") *)
val parse_file : string -> Ast.catalog
