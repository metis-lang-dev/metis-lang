type token =
  | Doc of string
  | Str of string
  | Arrow
  | HornSep
  | Ne
  | AtW
  | Range
  | Num of string
  | Ident of string
  | Punct of char

exception Lex_error of string

let is_letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_digit c = c >= '0' && c <= '9'
let is_ident_char c = is_letter c || is_digit c || c = '_' || c = '-'
let is_punct c = String.contains "{}().,*:[]~$|" c

let trim = String.trim

(* 1-based line:col of a character offset, for diagnostics *)
let line_col text offset =
  let line = ref 1 and bol = ref 0 in
  for k = 0 to min offset (String.length text) - 1 do
    if text.[k] = '\n' then begin incr line; bol := k + 1 end
  done;
  (!line, offset - !bol + 1)

let lex_fail text offset fmt =
  let (l, c) = line_col text offset in
  Printf.ksprintf (fun s ->
      raise (Lex_error (Printf.sprintf "%d:%d: %s" l c s))) fmt

let tokens_pos text =
  let n = String.length text in
  let out = ref [] and pos = ref [] in
  let i = ref 0 in
  let emit t = out := t :: !out; pos := !i :: !pos in
  let peek k = if !i + k < n then Some text.[!i + k] else None in
  let take_while p start =
    let j = ref start in
    while !j < n && p text.[!j] do incr j done;
    (String.sub text start (!j - start), !j) in
  while !i < n do
    let c = text.[!i] in
    if c = ' ' || c = '\t' || c = '\n' || c = '\r' then incr i
    else if c = '%' then begin
      (* %%doc | %comment; both run to end of line *)
      let (line, j) = take_while (fun ch -> ch <> '\n') !i in
      if String.length line >= 2 && line.[1] = '%' then
        emit (Doc (trim (String.sub line 2 (String.length line - 2))));
      i := j
    end
    else if c = '#' then begin
      (* #directive: the interpreter channel (embedded case lines);
         compiler-invisible, runs to end of line *)
      let (_, j) = take_while (fun ch -> ch <> '\n') !i in
      i := j
    end
    else if c = '"' then begin
      let (s, j) = take_while (fun ch -> ch <> '"' && ch <> '\n')
          (!i + 1) in
      if j >= n || text.[j] <> '"' then
        lex_fail text !i "unterminated string";
      emit (Str s); i := j + 1
    end
    else if c = '-' then begin
      (* only -o (arrow) may start with '-'; idents start with a
         letter and only CONTAIN hyphens *)
      match peek 1 with
      | Some 'o' when (match peek 2 with
          | Some c2 -> not (is_ident_char c2)
          | None -> true) -> emit Arrow; i := !i + 2
      | _ -> lex_fail text !i "bad character '-'"
    end
    else if c = ':' && peek 1 = Some '-' then begin
      emit HornSep; i := !i + 2 end
    else if c = '<' && peek 1 = Some '>' then begin
      emit Ne; i := !i + 2 end
    else if c = '@' then begin
      if peek 1 = Some 'w' then begin emit AtW; i := !i + 2 end
      else lex_fail text !i "bad character '@'"
    end
    else if c = '.' then begin
      match peek 1 with
      | Some '.' -> emit Range; i := !i + 2
      | Some d when is_digit d ->
        let (frac, j) = take_while is_digit (!i + 1) in
        emit (Num ("." ^ frac)); i := j
      | _ -> emit (Punct '.'); incr i
    end
    else if is_digit c then begin
      let (whole, j) = take_while is_digit !i in
      if j + 1 < n && text.[j] = '.' && is_digit text.[j + 1] then begin
        let (frac, k) = take_while is_digit (j + 1) in
        emit (Num (whole ^ "." ^ frac)); i := k
      end else begin emit (Num whole); i := j end
    end
    else if is_letter c then begin
      let (id, j) = take_while is_ident_char !i in
      emit (Ident id); i := j
    end
    else if is_punct c then begin emit (Punct c); incr i end
    else lex_fail text !i "bad character %C" c
  done;
  let offs = Array.of_list (List.rev !pos) in
  (List.rev !out, Array.map (line_col text) offs)

let tokens text = fst (tokens_pos text)
