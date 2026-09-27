(* Recursive-descent parser (00-language-spec §2). Docs attach to the
   next rule/link; range sugar expands in the AST. *)

exception Parse_error of string

val parse : string -> Ast.catalog
val parse_file : string -> Ast.catalog
