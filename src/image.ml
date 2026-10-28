(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/17 §3 — the image's files. See image.mli. *)

type j = JS of string | JI of int | JB of bool | JN | JL of j list | JO of (string * j) list

let esc s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c -> match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

let to_string v =
  let b = Buffer.create 4096 in
  let rec go ind = function
    | JS s -> Buffer.add_string b (esc s)
    | JI n -> Buffer.add_string b (string_of_int n)
    | JB x -> Buffer.add_string b (if x then "true" else "false")
    | JN -> Buffer.add_string b "null"
    | JL [] -> Buffer.add_string b "[]"
    | JO [] -> Buffer.add_string b "{}"
    | JL l when List.for_all (function JS _ | JI _ | JB _ | JN -> true | _ -> false) l ->
      (* a list of scalars on one line *)
      Buffer.add_char b '[';
      List.iteri (fun i x -> if i > 0 then Buffer.add_string b ", "; go ind x) l;
      Buffer.add_char b ']'
    | JL l ->
      Buffer.add_string b "[\n";
      List.iteri (fun i x ->
          if i > 0 then Buffer.add_string b ",\n";
          Buffer.add_string b (String.make (ind + 2) ' '); go (ind + 2) x) l;
      Buffer.add_string b ("\n" ^ String.make ind ' ' ^ "]")
    | JO m ->
      Buffer.add_string b "{\n";
      List.iteri (fun i (k, x) ->
          if i > 0 then Buffer.add_string b ",\n";
          Buffer.add_string b (String.make (ind + 2) ' ' ^ esc k ^ ": "); go (ind + 2) x) m;
      Buffer.add_string b ("\n" ^ String.make ind ' ' ^ "}") in
  go 0 v;
  Buffer.contents b ^ "\n"

let hash files =
  Sha256.hex (String.concat "" (List.map (fun (p, c) -> p ^ " " ^ Sha256.hex c ^ "\n") files))

let read_file p =
  let ic = open_in_bin p in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let write_file p s =
  let oc = open_out_bin p in
  output_string oc s; close_out oc

let rec mkdir_p d =
  if d <> "" && d <> "." && d <> "/" && not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    Sys.mkdir d 0o755
  end

(* ustar: a 512-byte header per file (name, mode, sizes in octal, a checksum
   over the header with its own field as spaces), the content padded to 512,
   two zero blocks at the end. Times are zero: the archive is a function of
   its files, so its bytes are reproducible. *)
let tar files =
  let b = Buffer.create 65536 in
  let pad n = Buffer.add_string b (String.make ((512 - n mod 512) mod 512) '\000') in
  List.iter (fun (name, data) ->
      if String.length name > 99 then failwith ("tar: a path over 99 bytes: " ^ name);
      let h = Bytes.make 512 '\000' in
      let put off s = Bytes.blit_string s 0 h off (String.length s) in
      put 0 name;
      put 100 "0000644\000";
      put 108 "0000000\000";
      put 116 "0000000\000";
      put 124 (Printf.sprintf "%011o\000" (String.length data));
      put 136 "00000000000\000";
      put 148 "        ";
      put 156 "0";
      put 257 "ustar\00000";
      let sum = ref 0 in
      Bytes.iter (fun c -> sum := !sum + Char.code c) h;
      put 148 (Printf.sprintf "%06o\000 " !sum);
      Buffer.add_bytes b h;
      Buffer.add_string b data;
      pad (String.length data))
    files;
  Buffer.add_string b (String.make 1024 '\000');
  Buffer.contents b
