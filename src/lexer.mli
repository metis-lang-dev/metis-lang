(* Hand-rolled tokenizer for rulescript v2 (00-language-spec §1).
   Mirrors parser.py _TOKEN; no regex dependency — a certifier ships
   with zero deps. *)

type token =
  | Doc of string          (* %% line, trimmed *)
  | Str of string          (* "..." without quotes *)
  | Arrow                  (* -o *)
  | HornSep                (* :- *)
  | Ne                     (* <> *)
  | AtW                    (* @w *)
  | Range                  (* .. *)
  | Num of string
  | Ident of string
  | Punct of char          (* one of {}().,*:[]~$ *)

exception Lex_error of string

val tokens : string -> token list
