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

let drive manifest per_case =
  let dir = Filename.dirname manifest in
  let ic = open_in manifest in
  let cur = ref (fresh ()) in
  (try
     while true do
       let l = String.trim (input_line ic) in
       if l = "" || l.[0] = '#' then ()
       else match split_ws l with
         | ["case"; n] -> !cur.c_name <- n
         | ["llp"; p] -> !cur.c_llp <- p
         | ["pack"; p] -> !cur.c_pack <- Some p
         | ["registry"; _] -> ()   (* bindings are native: referee-
                                      side only, never symbolic *)
         | ["init"; a; n] ->
           !cur.c_init <- !cur.c_init @ [(a, int_of_string n)]
         | ["steps"; n] -> !cur.c_steps <- int_of_string n
         | ["seeds"; n] -> !cur.c_seeds <- int_of_string n
         | ["unknown"; a] ->
           !cur.c_unknowns <- !cur.c_unknowns @ [a]
         | ["query"; a] -> !cur.c_queries <- a :: !cur.c_queries
         | "lik" :: clamps ->
           !cur.c_liks <- List.map parse_clamp clamps :: !cur.c_liks
         | ["end"] -> per_case dir !cur; cur := fresh ()
         | _ -> failwith ("bad manifest line: " ^ l)
     done
   with End_of_file -> close_in ic)

let () =
  match Array.to_list Sys.argv with
  | [_; "--selftest"] -> selftest ()
  | [_; "--keys"; manifest] -> drive manifest key_case
  | [_; "--roundtrip"; manifest] -> drive manifest roundtrip_case
  | [_; "--sample"; manifest] -> drive manifest sample_case
  | [_; manifest] -> drive manifest run_case
  | _ ->
    prerr_endline
      "usage: metisc <manifest> | --keys <manifest> | \
       --roundtrip <manifest> | --sample <manifest> | --selftest";
    exit 2
