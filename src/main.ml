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
  mutable c_liks : (string * int) list list }

let fresh () = { c_name = ""; c_llp = ""; c_pack = None;
                 c_init = []; c_steps = 0; c_seeds = 0;
                 c_unknowns = []; c_queries = []; c_liks = [] }

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

let build dir c =
  let base_ast = parse_llp dir c.c_llp in
  match c.c_pack with
  | None ->
    let (cat, ports) = Compile.compile base_ast in
    (cat, ports, Ground.ground cat c.c_init)
  | Some pp ->
    (* the pack path: compile base, compile pack against it, admit
       (containment), ground the merged catalog. Hooks come from the
       BASE ports (a pack that adds weight ports would merge them —
       out of corpus scope), horn from the merged catalog. *)
    let (bcat, bports) = Compile.compile base_ast in
    let pack_ast = parse_llp dir pp in
    let (pcat, _) =
      Compile.compile ~base:(bcat, base_ast) pack_ast in
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
      if Parser.parse (Ast.pretty a) <> a then begin
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
    c.c_init <- c.c_init @ [(a, int_of_string n)]; true
  | ["steps"; n] -> c.c_steps <- int_of_string n; true
  | ["seeds"; n] -> c.c_seeds <- int_of_string n; true
  | ["unknown"; a] -> c.c_unknowns <- c.c_unknowns @ [a]; true
  | ["query"; a] -> c.c_queries <- a :: c.c_queries; true
  | "lik" :: clamps ->
    c.c_liks <- List.map parse_clamp clamps :: c.c_liks; true
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
       let l = String.trim (input_line ic) in
       if String.length l > 0 && l.[0] = '#' then begin
         let body = String.trim
             (String.sub l 1 (String.length l - 1)) in
         match split_ws body with
         | [] -> ()
         | parts ->
           if not (case_line c parts) then
             failwith ("bad directive: " ^ l)
       end
     done
   with End_of_file -> close_in ic);
  c

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
  for seed = 1 to seeds do
    let (trace, final) = Refsample.run_trace prog c.c_steps seed in
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

let () =
  match Array.to_list Sys.argv with
  | [_; "--selftest"] -> selftest ()
  | [_; "--keys"; manifest] -> drive manifest key_case
  | [_; "--roundtrip"; manifest] -> drive manifest roundtrip_case
  | [_; "--sample"; manifest] -> drive manifest sample_case
  | [_; "--run"; llp] -> run_file llp
  | [_; manifest] -> drive manifest run_case
  | _ ->
    prerr_endline
      "usage: metisc <manifest> | --keys <manifest> | \
       --roundtrip <manifest> | --sample <manifest> | \
       --run <file.llp> | --selftest";
    exit 2
