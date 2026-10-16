(* SPDX-License-Identifier: Apache-2.0 *)
(* Case-manifest driver: the OCaml side of the parity gate
   (02-ocaml-contracts). Emits the symbolic wire for each case;
   compare against cpp/parity/ir_goldens.txt with referee floats
   stripped. Manifest paths resolve relative to the manifest file. *)

type case = {
  mutable c_name : string;
  mutable c_llp : string;
  mutable c_pack : string option;
  mutable c_init : (string * int) list;
  mutable c_steps : int;
  mutable c_seeds : int;
  mutable c_unknowns : string list;
  mutable c_queries : string list;
  mutable c_liks : (string * int) list list;
  mutable c_interactive : string list }

let fresh () = { c_name = ""; c_llp = ""; c_pack = None;
                 c_init = []; c_steps = 0; c_seeds = 0;
                 c_unknowns = []; c_queries = []; c_liks = [];
                 c_interactive = [] }

let split_ws s =
  List.filter (fun x -> x <> "") (String.split_on_char ' ' s)

let parse_clamp tok =
  match String.index_opt tok '=' with
  | Some i -> (String.sub tok 0 i,
               int_of_string
                 (String.sub tok (i + 1) (String.length tok - i - 1)))
  | None -> failwith ("bad clamp: " ^ tok)

let parse_llp dir p =
  let path = Filename.concat dir p in
  Compile.resolve_includes (Parser.parse_file path)
    (Filename.dirname path)

(* advisory compile warnings (never gating) go to stderr *)
let compile_warn ?base ast =
  let r = match base with
    | None -> Compile.compile ast
    | Some b -> Compile.compile ~base:b ast in
  List.iter (fun w -> prerr_endline ("warning: " ^ w)) (Compile.warnings ());
  r

let build dir c =
  let base_ast = parse_llp dir c.c_llp in
  match c.c_pack with
  | None ->
    let (cat, ports) = compile_warn base_ast in
    (cat, ports, Ground.ground cat c.c_init)
  | Some pp ->
    (* the pack path: compile base, compile pack against it, admit
       (containment), ground the merged catalog. Hooks come from the
       BASE ports (a pack that adds weight ports would merge them —
       out of corpus scope), horn from the merged catalog. *)
    let (bcat, bports) = compile_warn base_ast in
    let pack_ast = parse_llp dir pp in
    let (pcat, _) =
      compile_warn ~base:(bcat, base_ast) pack_ast in
    let merged = Catalog.admit bcat pcat in
    (merged, bports, Ground.ground merged c.c_init)

let run_case dir c =
  let (cat, ports, prog) = build dir c in
  let hooks_tbl = Ports.hooks prog ports cat in
  let hooks name = List.assoc_opt name hooks_tbl in
  let em = Factorize.emit prog c.c_steps hooks c.c_unknowns in
  List.iter print_endline
    (Ir.case_lines c.c_name em prog (List.rev c.c_queries)
       (List.rev c.c_liks))

let key_case dir c =
  let (_, _, prog) = build dir c in
  Printf.printf "K %s %s\n" c.c_name (Nets.program_key prog)

let roundtrip_case dir c =
  (* the interpretability contract: parse (pretty a) = a, checked on
     the UNRESOLVED source (includes stay declarations) *)
  List.iter (fun p ->
      let path = Filename.concat dir p in
      let a = Parser.parse_file path in
      (* locations are diagnostics-only: compare with them stripped *)
      if Ast.strip_locs (Parser.parse (Ast.pretty a))
         <> Ast.strip_locs a then begin
        Printf.eprintf "roundtrip FAILED: %s\n" p; exit 1
      end;
      Printf.printf "R %s ok\n" p)
    (c.c_llp :: (match c.c_pack with Some p -> [p] | None -> []))

let sample_case dir c =
  let (_, _, prog) = build dir c in
  Printf.printf "B %s %d %s\n" c.c_name c.c_steps
    (Nets.program_key prog);
  print_string (Nets.canonical_string prog);
  Printf.printf "E %d\n"
    (Array.length (Refsample.canonical_events prog));
  for seed = 1 to c.c_seeds do
    let (trace, final) = Refsample.run_trace prog c.c_steps seed in
    (match trace with
     | [] -> Printf.printf "R %d 0\n" seed
     | _ ->
       Printf.printf "R %d %d %s\n" seed (List.length trace)
         (String.concat " " (List.map string_of_int trace)));
    print_endline (Refsample.final_line seed final)
  done;
  print_endline "."

let selftest () =
  (* FIPS 180-4 vectors *)
  let want = [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991\
          b7852b855");
    ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410f\
             f61f20015ad") ] in
  List.iter (fun (s, w) ->
      if Sha256.hex s <> w then begin
        Printf.eprintf "sha256 selftest FAILED on %S\n" s; exit 1
      end)
    want;
  (* splitmix64 vectors (06-sampler-wire §3), seed 42 *)
  let st = ref 42L in
  List.iter (fun w ->
      let got = Printf.sprintf "%.17g" (Refsample.sm_unit st) in
      if got <> w then begin
        Printf.eprintf "splitmix selftest FAILED: %s <> %s\n"
          got w; exit 1
      end)
    ["0.74156487877182331"; "0.1599103928769201";
     "0.27860113025513866"];
  print_endline "selftest ok"

(* the case vocabulary shared by manifests and '#'-directives
   embedded in a .llp (00-language-spec §7): ONE line syntax, so the
   interpreter can never drift from the manifest driver *)
let case_line c = function
  | ["init"; a; n] ->
    (* one count per atom: a repeated init replaces it in place
       (metispy's dict) *)
    let n = int_of_string n in
    c.c_init <- (if List.mem_assoc a c.c_init
                 then List.map (fun (x, m) -> (x, if x = a then n else m))
                     c.c_init
                 else c.c_init @ [(a, n)]); true
  | ["steps"; n] -> c.c_steps <- int_of_string n; true
  | ["seeds"; n] -> c.c_seeds <- int_of_string n; true
  | ["unknown"; a] -> c.c_unknowns <- c.c_unknowns @ [a]; true
  | ["query"; a] -> c.c_queries <- a :: c.c_queries; true
  | "lik" :: clamps ->
    c.c_liks <- List.map parse_clamp clamps :: c.c_liks; true
  | ["interactive"; s] ->
    (* the additive &: the named stage's CHOICE is resolved by the
       environment, not the sampler ('--run' only; the symbolic
       drivers ignore it) *)
    c.c_interactive <- c.c_interactive @ [s]; true
  | _ -> false

let drive manifest per_case =
  let dir = Filename.dirname manifest in
  let ic = open_in manifest in
  let cur = ref (fresh ()) in
  (try
     while true do
       let l = String.trim (input_line ic) in
       if l = "" || l.[0] = '#' then ()
       else if case_line !cur (split_ws l) then ()
       else match split_ws l with
         | ["case"; n] -> !cur.c_name <- n
         | ["llp"; p] -> !cur.c_llp <- p
         | ["pack"; p] -> !cur.c_pack <- Some p
         | ["registry"; _] -> ()   (* bindings are native: referee-
                                      side only, never symbolic *)
         | ["end"] -> per_case dir !cur; cur := fresh ()
         | _ -> failwith ("bad manifest line: " ^ l)
     done
   with End_of_file -> close_in ic)

(* `#init at(e0, f0) 1` -> `#init at(e0,f0) 1`: whitespace inside an
   atom's innermost parentheses is formatting, never a token boundary
   (metispy directives.squash_atoms) *)
let squash_atoms l =
  let b = Buffer.create (String.length l) in
  let n = String.length l in
  let i = ref 0 in
  while !i < n do
    (if l.[!i] = '(' then
       (* an innermost group: no '(' before its ')' *)
       match String.index_from_opt l (!i + 1) ')' with
       | Some j when not (String.contains (String.sub l (!i + 1)
                                              (j - !i - 1)) '(') ->
         Buffer.add_char b '(';
         String.iter (fun ch ->
             if not (List.mem ch [' '; '\t'; '\n'; '\r'; '\x0b'; '\x0c'])
             then Buffer.add_char b ch)
           (String.sub l (!i + 1) (j - !i - 1));
         Buffer.add_char b ')';
         i := j
       | _ -> Buffer.add_char b '('
     else Buffer.add_char b l.[!i]);
    incr i
  done;
  Buffer.contents b

(* a directive's tokens: python str.split() over the squashed line *)
let split_any_ws s =
  List.filter (fun x -> x <> "")
    (String.split_on_char ' '
       (String.map (fun ch ->
            if List.mem ch ['\t'; '\n'; '\r'; '\x0b'; '\x0c'] then ' '
            else ch) s))

(* --run: a .llp carrying its own case as '#'-directives (lines whose
   first non-blank char is '#'; the lexer drops them, so the compiled
   catalog and its key are identical with or without them). *)
let embedded_case path =
  let ic = open_in path in
  let c = fresh () in
  c.c_name <- Filename.remove_extension (Filename.basename path);
  c.c_llp <- Filename.basename path;
  (try
     while true do
       let l = squash_atoms (String.trim (input_line ic)) in
       if String.length l > 0 && l.[0] = '#' then begin
         let body = String.trim
             (String.sub l 1 (String.length l - 1)) in
         match split_any_ws body with
         | [] -> ()
         | ["plugin"; _] | ["notch"; _] -> ()
           (* the interpreter's: the port plugin and a fitted notch
              overlay bind weights in the REPL (PLUGIN-PORTS.md);
              bindings are referee-side only, never symbolic (as the
              manifest's 'registry') *)
         | parts ->
           if not (case_line c parts) then
             failwith ("bad directive: " ^ l)
       end
     done
   with End_of_file -> close_in ic);
  c

(* --diagnostics / --diagnostics-json FILE.llp: compile (includes
   resolved) and list every structured diagnostic (spec 08) — the
   listing is the command's job, so exit 0 whether the compile failed
   or not; the D2 parity gate diffs this against the goldens *)
let diagnostics_file ?base ~json path =
  let load p = Compile.resolve_includes (Parser.parse_file p)
      (Filename.dirname p) in
  (* a pack's BASE must compile: its failure is NOT the pack's
     diagnostics — it propagates (main prints it, exit 1), exactly as
     metispy diagnose() raises *)
  let based = match base with
    | None -> None
    | Some b -> let bast = load b in Some (fst (Compile.compile bast), bast) in
  Diag.reset ();
  (try
     match based with
     | None -> ignore (Compile.compile (load path))
     | Some (bcat, bast) ->
       (* compile the pack against the base, then admit — admission
          diagnostics join *)
       let (pcat, _) = Compile.compile ~base:(bcat, bast) (load path) in
       ignore (Catalog.admit bcat pcat)
   with Compile.Lang_error _ | Catalog.Catalog_error _ -> ());
  List.iter (fun d ->
      if json then print_endline (Diag.to_json d)
      else print_string (Diag.render_text d))
    (Compile.diagnostics ())

let run_file path =
  let c = embedded_case path in
  if c.c_steps = 0 then failwith "no #steps directive";
  let seeds = if c.c_seeds = 0 then 1 else c.c_seeds in
  let (_, _, prog) = build (Filename.dirname path) c in
  Printf.printf "case %s steps=%d seeds=%d\n"
    c.c_name c.c_steps seeds;
  List.iter (fun (a, n) -> Printf.printf "I %s %d\n" a n) c.c_init;
  let events = Refsample.canonical_events prog in
  let queries = List.rev c.c_queries in
  let hits = List.map (fun q -> (q, ref 0)) queries in
  (* '#interactive <stage>': menu on stderr, selection from stdin;
     EOF or junk falls back to the sampler draw, so piped runs
     complete. The T/F/Q wire on stdout is unchanged. *)
  let pick stage ws total =
    if not (List.mem stage c.c_interactive) then None
    else begin
      Printf.eprintf "-- %s: choose an event --\n" stage;
      List.iteri (fun k (i, w) ->
          Printf.eprintf "  %d) %s  (p=%.3f)\n" (k + 1)
            events.(i).Refsample.ev.Ground.ev_name (w /. total)) ws;
      Printf.eprintf "> %!";
      match input_line stdin with
      | exception End_of_file ->
        prerr_endline "(eof: sampler)"; None
      | l ->
        (match int_of_string_opt (String.trim l) with
         | Some k when k >= 1 && k <= List.length ws ->
           Some (fst (List.nth ws (k - 1)))
         | _ -> prerr_endline "(unrecognized: sampler)"; None)
    end in
  for seed = 1 to seeds do
    let (trace, final) =
      Refsample.run_trace_pick prog c.c_steps seed ~pick in
    Printf.printf "T %d %s\n" seed
      (match trace with
       | [] -> "-"
       | _ -> String.concat " "
                (List.map (fun i ->
                     events.(i).Refsample.ev.Ground.ev_name) trace));
    print_endline (Refsample.final_line seed final);
    let (_, kappa) = final in
    List.iter (fun (q, r) ->
        if List.exists (fun (a, n) -> a = q && n > 0) kappa then
          incr r)
      hits
  done;
  List.iter (fun (q, r) ->
      Printf.printf "Q %s %d/%d\n" q !r seeds)
    hits

(* --wire PROGRAM.llp [--extension E.llp]...: a domain package's served
   program as the product ground wire (bundle-compiler step 1) — the
   program compiled with its includes, every extension compiled against
   the world so far and admitted over it, the ports merged (metispy
   served_doc), grounded on the program's #init, S its #steps; stdout *)
let wire_file program extensions =
  let c = embedded_case program in
  let load p = Compile.resolve_includes (Parser.parse_file p)
      (Filename.dirname p) in
  let past = load program in
  let (cat, ports) = compile_warn past in
  let (cat, ports, _) = List.fold_left (fun (cat, ports, (bast : Ast.catalog)) e ->
      let east = load e in
      let (ecat, eports) = compile_warn ~base:(cat, bast) east in
      (Catalog.admit cat ecat, Wire.merge_ports ports eports,
       { bast with Ast.cdecls = bast.Ast.cdecls @ east.Ast.cdecls;
                   cdecl_locs = bast.Ast.cdecl_locs @ east.Ast.cdecl_locs }))
      (cat, ports, past) extensions in
  let prog = Ground.ground cat c.c_init in
  List.iter print_endline (Wire.artifact_lines cat ports prog c.c_steps)

let rec wire_args program exts = function
  | [] -> wire_file program (List.rev exts)
  | "--extension" :: e :: rest -> wire_args program (e :: exts) rest
  | a :: _ -> failwith ("--wire: unknown argument " ^ a)

let () =
  (try match Array.to_list Sys.argv with
  | _ :: "--wire" :: program :: rest -> wire_args program [] rest
  | [_; "--selftest"] -> selftest ()
  | [_; "--keys"; manifest] -> drive manifest key_case
  | [_; "--roundtrip"; manifest] -> drive manifest roundtrip_case
  | [_; "--sample"; manifest] -> drive manifest sample_case
  | [_; "--run"; llp] -> run_file llp
  | [_; "--diag-registry"] ->
    (* code severity migrated|pending — diffed by metispy so the two
       registries cannot drift *)
    List.iter (fun (c, (sev, phase)) ->
        Printf.printf "%s %s %s\n" c sev phase) Diag.registry
  | [_; "--diagnostics"; llp] -> diagnostics_file ~json:false llp
  | [_; "--diagnostics"; llp; "--base"; b] ->
    diagnostics_file ~base:b ~json:false llp
  | [_; "--diagnostics-json"; llp; "--base"; b] ->
    diagnostics_file ~base:b ~json:true llp
  | [_; "--diagnostics-json"; llp] -> diagnostics_file ~json:true llp
  | [_; manifest] -> drive manifest run_case
  | _ ->
    prerr_endline
      "usage: metisc <manifest> | --keys <manifest> | \
       --roundtrip <manifest> | --sample <manifest> | \
       --run <file.llp> | --wire <program.llp> [--extension \
       <e.llp>]... | --diagnostics[-json] <file.llp> [--base \
       <base.llp>] | --diag-registry | --selftest\n\
       (--diagnostics* LIST diagnostics and exit 0 even when errors are \
       listed — a listing, not a compile; use --run or a manifest for \
       pass/fail)";
    exit 2
   with
   | Compile.Lang_error msgs ->
     List.iter (fun m -> prerr_endline ("error: " ^ m)) msgs; exit 1
   | Parser.Parse_error m ->
     prerr_endline ("parse error: " ^ m); exit 1
   | Lexer.Lex_error m ->
     prerr_endline ("lex error: " ^ m); exit 1
   | Failure m -> prerr_endline ("error: " ^ m); exit 1)
