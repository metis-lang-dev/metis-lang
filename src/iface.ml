(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/15 §6 — the interface check over a composition manifest: the
   static rule×pred graph (§1), checks I1–I12 (§3, §8, §10) with the
   cut report, each member's external interface EI(S) and ei_key
   (§10.3), the package key (§8.1). A listing, not spec 08 rows: the
   iface-* codes do not exist yet (the two-repo registry). *)

open Ast

(* -- a YAML subset: what the composer writes, and nothing else --------
   `key: value` at column 0; values are a bare or quoted scalar, a flow
   list [a, b] or a flow map {k: v}, nested; `#` lines are comments.
   Block YAML is refused with its line number. *)

type y = S of string | L of y list | M of (string * y) list

exception Yaml_error of string

let flow file lno s =
  let n = String.length s in
  let err fmt = Printf.ksprintf (fun m ->
      raise (Yaml_error (Printf.sprintf "%s:%d: %s" file lno m))) fmt in
  let rec ws i = if i < n && (s.[i] = ' ' || s.[i] = '\t') then ws (i + 1) else i in
  let scalar i stops =
    let i = ws i in
    if i < n && s.[i] = '"' then begin
      let b = Buffer.create 16 in
      let rec go j =
        if j >= n then err "unterminated quote"
        else if s.[j] = '\\' && j + 1 < n then (Buffer.add_char b s.[j + 1]; go (j + 2))
        else if s.[j] = '"' then (Buffer.contents b, j + 1)
        else (Buffer.add_char b s.[j]; go (j + 1)) in
      go (i + 1)
    end else begin
      (* an atom's parentheses hold its commas: `look(target, p0)` is one
         scalar *)
      let j = ref i and depth = ref 0 in
      while !j < n && (!depth > 0 || not (String.contains stops s.[!j])) do
        (if s.[!j] = '(' then incr depth
         else if s.[!j] = ')' && !depth > 0 then decr depth);
        incr j
      done;
      (String.trim (String.sub s i (!j - i)), !j)
    end in
  let rec value i =
    let i = ws i in
    if i < n && s.[i] = '[' then list (i + 1) []
    else if i < n && s.[i] = '{' then map (i + 1) []
    else let (v, j) = scalar i ",]}" in (S v, j)
  and list i acc =
    let i = ws i in
    if i < n && s.[i] = ']' then (L (List.rev acc), i + 1)
    else
      let (v, j) = value i in
      let j = ws j in
      if j < n && s.[j] = ',' then list (j + 1) (v :: acc)
      else if j < n && s.[j] = ']' then (L (List.rev (v :: acc)), j + 1)
      else err "expected , or ] in a flow list"
  and map i acc =
    let i = ws i in
    if i < n && s.[i] = '}' then (M (List.rev acc), i + 1)
    else
      let (k, j) = scalar i ":,}" in
      if not (j < n && s.[j] = ':') then err "expected key: value in a flow map";
      let (v, j) = value (j + 1) in
      let j = ws j in
      if j < n && s.[j] = ',' then map (j + 1) ((k, v) :: acc)
      else if j < n && s.[j] = '}' then (M (List.rev ((k, v) :: acc)), j + 1)
      else err "expected , or } in a flow map" in
  let (v, j) = value 0 in
  if ws j <> n then err "trailing text after a flow value";
  v

(* a `#` after whitespace, outside quotes, starts a comment *)
let strip_comment rest =
  let n = String.length rest in
  let rec cut j q =
    if j >= n then rest
    else if rest.[j] = '"' then cut (j + 1) (not q)
    else if (not q) && rest.[j] = '#'
            && (j = 0 || rest.[j - 1] = ' ' || rest.[j - 1] = '\t')
    then String.sub rest 0 j
    else cut (j + 1) q in
  String.trim (cut 0 false)

let leaf file lno rest =
  if rest.[0] = '[' || rest.[0] = '{' then flow file lno rest
  else if String.length rest >= 2 && rest.[0] = '"' && rest.[String.length rest - 1] = '"'
  then S (String.sub rest 1 (String.length rest - 2))
  else S rest

(* a flow value may run over several lines: a line whose brackets are
   left open (outside quotes) takes the next lines until they close *)
let continued lines =
  let depth s =
    let d = ref 0 and q = ref false in
    String.iter (fun c ->
        if c = '"' then q := not !q
        else if not !q then
          (if c = '[' || c = '{' then incr d else if c = ']' || c = '}' then decr d)) s;
    !d in
  let rec go acc = function
    | [] -> List.rev acc
    | (lno, l) :: tl ->
      let t = String.trim l in
      if t = "" || t.[0] = '#' then go ((lno, l) :: acc) tl
      else
        let rec more line d tl =
          if d <= 0 then (line, tl)
          else match tl with
            | [] -> (line, [])
            | (_, l') :: tl' -> more (line ^ " " ^ String.trim l') (d + depth l') tl' in
        let (line, tl) = more l (depth l) tl in
        go ((lno, line) :: acc) tl in
  go [] lines

(* the instrument's case and manifest reader (spec/16 §5): the subset
   above, plus block MAPPINGS — `key:` alone on its line opens a map
   whose entries are indented below it, at one indentation; leaves are
   scalars and flow values. Block lists (`- x`) stay refused. *)
let read_yaml_block file =
  let ic = open_in_bin file in
  let raw = ref [] in
  (try while true do raw := input_line ic :: !raw done
   with End_of_file -> close_in ic);
  let err lno fmt = Printf.ksprintf (fun m ->
      raise (Yaml_error (Printf.sprintf "%s:%d: %s" file lno m))) fmt in
  let lines = List.filter_map (fun (lno, l) ->
      let t = String.trim l in
      if t = "" || t.[0] = '#' then None
      else begin
        let ind = ref 0 in
        while !ind < String.length l && l.[!ind] = ' ' do incr ind done;
        if l.[!ind] = '\t' then err lno "a tab in the indentation";
        if t.[0] = '-' then err lno "a block list is not read here (a flow list [a, b])";
        match String.index_opt t ':' with
        | None -> err lno "expected key: value"
        | Some i ->
          let key = String.trim (String.sub t 0 i) in
          let key = if String.length key >= 2 && key.[0] = '"'
                       && key.[String.length key - 1] = '"'
            then String.sub key 1 (String.length key - 2) else key in
          Some (lno, !ind, key,
                strip_comment (String.sub t (i + 1) (String.length t - i - 1)))
      end)
      (continued (List.mapi (fun k l -> (k + 1, l)) (List.rev !raw))) in
  let rec map_at ind acc = function
    | (lno, i, _, _) :: _ when i > ind -> err lno "unexpected indentation"
    | (lno, i, key, rest) :: tl when i = ind ->
      if rest <> "" then map_at ind ((key, leaf file lno rest) :: acc) tl
      else (match tl with
          | (_, j, _, _) :: _ when j > ind ->
            let (child, tl') = map_at j [] tl in
            map_at ind ((key, M child) :: acc) tl'
          | _ -> err lno "%s: an empty value" key)
    | tl -> (List.rev acc, tl) in
  match map_at 0 [] lines with
  | (m, []) -> m
  | (_, (lno, _, _, _) :: _) -> err lno "unexpected indentation"

let read_yaml file =
  let ic = open_in_bin file in
  let lines = ref [] in
  (try while true do lines := input_line ic :: !lines done
   with End_of_file -> close_in ic);
  let out = ref [] in
  List.iteri (fun k l ->
      let lno = k + 1 in
      let t = String.trim l in
      if t = "" || t.[0] = '#' then ()
      else if l.[0] = ' ' || l.[0] = '\t' || l.[0] = '-' then
        raise (Yaml_error (Printf.sprintf "%s:%d: block YAML is not read here \
                                           (one `key: value` per line, flow \
                                           lists and maps)" file lno))
      else match String.index_opt l ':' with
        | None -> raise (Yaml_error (Printf.sprintf "%s:%d: expected key: value" file lno))
        | Some i ->
          let key = String.trim (String.sub l 0 i) in
          let rest = String.sub l (i + 1) (String.length l - i - 1) in
          (* a `#` after whitespace, outside quotes, starts a comment *)
          let rest =
            let n = String.length rest in
            let rec cut j q =
              if j >= n then rest
              else if rest.[j] = '"' then cut (j + 1) (not q)
              else if (not q) && rest.[j] = '#'
                      && (j = 0 || rest.[j - 1] = ' ' || rest.[j - 1] = '\t')
              then String.sub rest 0 j
              else cut (j + 1) q in
            String.trim (cut 0 false) in
          if rest = "" then
            raise (Yaml_error (Printf.sprintf "%s:%d: %s: an empty value (block \
                                               YAML is not read here)" file lno key));
          let v = if rest.[0] = '[' || rest.[0] = '{' then flow file lno rest
            else S (let (s, _) = (rest, 0) in
                    if String.length s >= 2 && s.[0] = '"' && s.[String.length s - 1] = '"'
                    then String.sub s 1 (String.length s - 2) else s) in
          out := (key, v) :: !out)
    (List.rev !lines);
  List.rev !out

let str = function S s -> s | _ -> raise (Yaml_error "expected a scalar")
let strs = function L l -> List.map str l | S "" -> [] | _ -> raise (Yaml_error "expected a list")
let pairs = function M m -> m | _ -> raise (Yaml_error "expected a map")

(* -- paths ----------------------------------------------------------- *)

let norm p =
  let p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p in
  let parts = String.split_on_char '/' p in
  let st = List.fold_left (fun acc x ->
      match x with
      | "" | "." -> acc
      | ".." -> (match acc with _ :: r -> r | [] -> [])
      | x -> x :: acc) [] parts in
  "/" ^ String.concat "/" (List.rev st)

(* p relative to the directory base: "../x" when p lies outside it, so
   the listing never carries an absolute path (it is a golden) *)
let rel base p =
  let split x = List.filter (( <> ) "") (String.split_on_char '/' (norm x)) in
  let rec drop a b = match a, b with
    | x :: a', y :: b' when x = y -> drop a' b'
    | _ -> (a, b) in
  let (up, down) = drop (split base) (split p) in
  String.concat "/" (List.map (fun _ -> "..") up @ down)

(* -- a member: its files, declarations and rules ---------------------- *)

type rrule = {
  r_name : string; r_file : string;
  r_body : (atom * char) list;          (* c consume | r read | g guard *)
  r_head : atom list }

type member = {
  m_name : string; m_role : string;     (* specialist | direct *)
  m_program : string;                   (* normalized path *)
  m_files : string list;                (* the include closure, DFS order *)
  m_includes : (string * string) list;  (* edges: file -> included file *)
  m_decl_file : (string * string) list; (* pred/bwd name -> declaring file *)
  m_sigs : (string * string list) list;
  m_bwd : string list;
  m_types : (string * string list) list;
  m_abstract : string list;
  m_rules : rrule list;
  m_init : (string * int) list;         (* #init directives of the program *)
  m_facts : atom list;                  (* Horn facts (the director's relay table) *)
  m_shared : (string * string) list;
  m_status : (string * string list) list;
  m_extra : (string * y) list;          (* the rest of domain.yaml *)
  m_key : string;                       (* the resolved AST's sha256 *)
  m_compile : string option;            (* None: compiles *)
  m_inc : (string * string * string) list; (* include string, place, file *)
  m_inc_err : string list }             (* includes that resolve nowhere *)

let init_of path =
  let ic = open_in_bin path in
  let out = ref [] in
  (try while true do
       let l = String.trim (input_line ic) in
       match List.filter (( <> ) "") (String.split_on_char ' ' l) with
       | ["#init"; a; n] -> out := (a, int_of_string n) :: !out
       | _ -> ()
     done with End_of_file -> close_in ic);
  List.rev !out

let load_member dir name role =
  let pkg = Filename.concat dir name in
  let man = read_yaml (Filename.concat pkg "domain.yaml") in
  let program = match List.assoc_opt "program" man with
    | Some v -> norm (Filename.concat pkg (str v))
    | None -> raise (Yaml_error (name ^ "/domain.yaml: no program")) in
  let files = ref [] and edges = ref [] and decl_file = ref [] in
  let sigs = ref [] and bwd = ref [] and types = ref [] and abstract = ref [] in
  let rules = ref [] and facts = ref [] in
  let incs = ref [] and inc_err = ref [] in
  let rec visit f =
    if not (List.mem f !files) then begin
      files := !files @ [f];
      let ast = Parser.parse_file f in
      List.iter (fun d ->
          match d with
          | DInclude p ->
            (match Compile.include_place p (Filename.dirname f) with
             | (place, g) ->
               let g = norm g in
               if not (List.exists (fun (_, _, q) -> q = g) !incs) then
                 incs := !incs @ [(p, place, g)];
               edges := !edges @ [(f, g)]; visit g
             | exception Compile.Lang_error ms -> inc_err := !inc_err @ ms)
          | DPred (n, a, _) ->
            if not (List.mem_assoc n !decl_file) then decl_file := !decl_file @ [(n, f)];
            sigs := !sigs @ [(n, a)]
          | DBwd (n, a) ->
            if not (List.mem_assoc n !decl_file) then decl_file := !decl_file @ [(n, f)];
            sigs := !sigs @ [(n, a)]; bwd := n :: !bwd
          | DType (n, cs) -> types := !types @ [(n, cs)]
          | DTypes ns -> abstract := !abstract @ ns
          | DFact a -> facts := !facts @ [a]
          | DStage s ->
            List.iter (fun (r : rule) ->
                rules := !rules @ [{ r_name = r.rname; r_file = f;
                                     r_body = List.filter_map (function
                                         | BAtom a -> Some (a, if a.persist then 'r' else 'c')
                                         | BDistinct _ -> None) r.rbody;
                                     r_head = r.rhead }])
              s.srules
          | DLink l ->
            rules := !rules @ [{ r_name = l.lname; r_file = f;
                                 r_body = List.map (fun (a : atom) ->
                                     (a, if a.persist then 'r' else 'c')) l.lpre_atoms;
                                 r_head = l.lpost_atoms }]
          | _ -> ())
        ast.cdecls
    end in
  visit program;
  (* a bwd atom is a guard whatever its marker (cs_guards) *)
  let rules = List.map (fun r ->
      { r with r_body = List.map (fun (a, k) ->
            (a, if List.mem a.pred !bwd then 'g' else k)) r.r_body }) !rules in
  let (key, compile) =
    match Compile.resolve_includes (Parser.parse_file program) (Filename.dirname program) with
    | exception e -> ("-", Some (Printexc.to_string e))
    | ast ->
      let key = Sha256.hex (Ast.pretty (Ast.strip_locs ast)) in
      (key, match Compile.compile ast with
        | _ -> None
        | exception Compile.Lang_error ms -> Some (String.concat "; " ms)
        | exception Catalog.Catalog_error ms -> Some (String.concat "; " ms)) in
  let field k f = match List.assoc_opt k man with Some v -> f v | None -> [] in
  { m_name = name; m_role = role; m_program = program;
    m_files = !files; m_includes = !edges; m_decl_file = !decl_file;
    m_sigs = !sigs; m_bwd = !bwd; m_types = !types; m_abstract = !abstract;
    m_rules = rules; m_init = init_of program; m_facts = !facts;
    m_shared = field "shared" (fun v -> List.map (fun (k, d) -> (k, str d)) (pairs v));
    m_status = field "status" (fun v -> List.map (fun (k, l) -> (k, strs l)) (pairs v));
    m_extra = List.filter (fun (k, _) -> not (List.mem k ["shared"; "status"])) man;
    m_key = key; m_compile = compile; m_inc = !incs; m_inc_err = !inc_err }

(* a pred's roles in a member: the labels of its edges *)
let roles m p =
  let s = ref [] in
  let add c = if not (List.mem c !s) then s := c :: !s in
  List.iter (fun r ->
      List.iter (fun ((a : atom), k) -> if a.pred = p then add k) r.r_body;
      List.iter (fun (a : atom) -> if a.pred = p then add 'o') r.r_head)
    m.m_rules;
  let l = List.sort compare !s in
  String.concat "" (List.map (String.make 1) l)

let has c s = String.contains s c

(* -- the interface packages --------------------------------------------- *)

type ipkg = { i_path : string; i_name : string; i_key : string;
              i_preds : string list; i_rules : bool;
              i_nature : (string * string) list option }

let load_ipkg path =
  let ast = Parser.parse_file path in
  let preds = List.filter_map (function
      | DPred (n, _, _) | DBwd (n, _) -> Some n | _ -> None) ast.cdecls in
  let rules = List.exists (function
      | DStage _ | DLink _ | DFact _ | DHorn _ -> true | _ -> false) ast.cdecls in
  let side = Filename.remove_extension path ^ ".yaml" in
  let nature =
    if Sys.file_exists side then
      Option.map (fun v -> List.map (fun (k, d) -> (k, str d)) (pairs v))
        (List.assoc_opt "nature" (read_yaml side))
    else None in
  (* the key covers the declarations AND the natures (ruled): a nature
     change is visible to I12 and to OTA compatibility *)
  let nature_line = match nature with
    | None -> ""
    | Some n ->
      "nature: {" ^ String.concat ", "
        (List.map (fun (k, d) -> k ^ ": " ^ d) (List.sort compare n)) ^ "}\n" in
  { i_path = path; i_name = ast.cname;
    i_key = Sha256.hex (Ast.pretty (Ast.strip_locs ast) ^ nature_line);
    i_preds = preds; i_rules = rules; i_nature = nature }

(* -- the check -------------------------------------------------------- *)

type finding = { sev : string; chk : string; text : string }

let run comp_path =
  let dir = Filename.dirname (norm comp_path) in
  let comp = read_yaml comp_path in
  let get k = match List.assoc_opt k comp with
    | Some v -> v
    | None -> raise (Yaml_error (comp_path ^ ": no " ^ k)) in
  let opt k = List.assoc_opt k comp in
  let specialists = strs (get "specialists") in
  let direct = str (get "direct") in
  let world = match opt "world" with Some v -> pairs v | None -> [] in
  let world_out = match List.assoc_opt "out" world with Some v -> strs v | None -> [] in
  let world_in = match List.assoc_opt "in" world with Some v -> strs v | None -> [] in
  let resolve p =
    match Compile.include_place p dir with
    | (place, f) -> (place, norm f)
    | exception Compile.Lang_error ms -> raise (Yaml_error (String.concat "; " ms)) in
  let capacity = snd (resolve (str (get "capacity"))) in
  let ipaths =
    (match opt "protocol" with Some v -> [str v] | None -> [])
    @ (match opt "interfaces" with Some v -> strs v | None -> []) in
  let ipkgs = List.map (fun p -> load_ipkg (snd (resolve p))) ipaths in
  let members = List.map (fun n -> load_member dir n "specialist") specialists
                @ [load_member dir direct "direct"] in
  let specs = List.filter (fun m -> m.m_role = "specialist") members in
  let dm = List.find (fun m -> m.m_role = "direct") members in
  let findings = ref [] in
  let add sev chk fmt = Printf.ksprintf (fun text ->
      findings := { sev; chk; text } :: !findings) fmt in
  let ipath_of_file f = List.find_opt (fun i -> i.i_path = f) ipkgs in
  let iface_owner p =
    List.filter (fun i -> List.mem p i.i_preds) ipkgs in
  (* the shared map's crossing entries: in/out preds (world-private and
     resources are not crossing preds) *)
  let crossing m = List.filter (fun (_, d) -> d = "in" || d = "out") m.m_shared in
  let own_decl m p =
    match List.assoc_opt p m.m_decl_file with
    | Some f -> ipath_of_file f = None
    | None -> false in
  (* a path as the listing shows it: under METIS_HOME as home:<path>,
     else relative to the composition's directory *)
  let home = match Sys.getenv_opt "METIS_HOME" with
    | Some h when h <> "" -> Some (norm h) | _ -> None in
  let show f = match home with
    | Some h when String.length f > String.length h
                  && String.sub f 0 (String.length h + 1) = h ^ "/" -> "home:" ^ rel h f
    | _ -> rel dir f in
  (* includes that resolve nowhere *)
  List.iter (fun m ->
      List.iter (fun e -> add "error" "include" "%s: %s" m.m_name e) m.m_inc_err) members;
  let shared_bases = ref [] in
  (* compile *)
  List.iter (fun m -> match m.m_compile with
      | Some e -> add "error" "compile" "%s: does not compile: %s" m.m_name e
      | None -> ()) members;
  (* I1 private stays private *)
  let declared_by p = List.filter (fun m -> List.mem_assoc p m.m_sigs && own_decl m p) members in
  let all_shared = List.sort_uniq compare
      (List.concat_map (fun m -> List.map fst (crossing m)) members) in
  List.iter (fun p ->
      let ds = declared_by p in
      let listing = List.filter (fun m -> List.mem_assoc p (crossing m)) ds in
      let unlisted = List.filter (fun m ->
          not (List.mem_assoc p m.m_shared)) ds in
      if listing <> [] && unlisted <> [] then
        List.iter (fun m ->
            add "error" "I1" "%s: declares %s without listing it; shared by %s"
              m.m_name p (String.concat ", " (List.map (fun m -> m.m_name) listing)))
          unlisted)
    all_shared;
  (* I2 direction agrees with the roles *)
  List.iter (fun m ->
      List.iter (fun (p, d) ->
          let r = roles m p in
          match d with
          | "in" | "out" when not (List.mem_assoc p m.m_sigs) ->
            add "error" "I2" "%s: %s %s names no declared pred" m.m_name d p
          | "in" ->
            if has 'o' r && not (has 'c' r) then
              add "error" "I2" "%s: in %s is produced by its own rules (roles %s) and never consumed" m.m_name p r
            else if r = "" then
              add "warning" "I2" "%s: in %s is read by no rule (in-unread)" m.m_name p
          | "out" ->
            if not (has 'o' r) then
              add "error" "I2" "%s: out %s is produced by no rule (roles %s)" m.m_name p
                (if r = "" then "-" else r)
          | "resource" ->
            if r <> "" then
              add "error" "I2" "%s: resource %s appears in its rules (roles %s): requests only" m.m_name p r
          | "world-private" -> ()
          | d -> add "error" "I2" "%s: %s has the unknown direction %s" m.m_name p d)
        m.m_shared)
    members;
  (* I3 every in has a producer *)
  (* what the direct member produces: its rule heads, and the kinds its
     relay table sends (today's director: detour(K1, K2) sends K2,
     rename(K1, K2, G) sends G — the host forwards an atom by its kind) *)
  let d_rule_heads =
    List.concat_map (fun r -> List.map (fun (a : atom) -> a.pred) r.r_head) dm.m_rules in
  (* TRANSITIONAL (ruled, step 1c): until §8.4's goal(S, K) replaces them *)
  let d_relay = List.filter_map (fun (a : atom) ->
      match a.pred, a.terms with
      | "detour", [_; TConst k] -> Some k
      | "rename", [_; _; TConst g] -> Some g
      | _ -> None) dm.m_facts in
  let d_heads = d_rule_heads @ d_relay in
  (* the host asserts the status report (spec/15 amendment 1b) *)
  let host_out = List.filter (fun p -> p = "tick__status")
      (List.concat_map (fun i -> i.i_preds) ipkgs) in
  List.iter (fun m ->
      List.iter (fun (p, d) ->
          if d = "in" then begin
            let peer = List.exists (fun m' ->
                m'.m_name <> m.m_name && List.assoc_opt p m'.m_shared = Some "out") members in
            if not (peer || List.mem p world_out || List.mem p d_heads || List.mem p host_out) then begin
              (* ruled (step 3b): a protocol REPORT nobody sends is a
                 warning (tick__active/tick__stuck in a sequential
                 composition); signals and resources keep the error *)
              let nature = List.find_map (fun i ->
                  match i.i_nature with
                  | Some n when List.mem p i.i_preds -> List.assoc_opt p n
                  | _ -> None) ipkgs in
              if nature = Some "report" then
                add "warning" "I3" "%s: in %s is a report nobody sends" m.m_name p
              else
                add "error" "I3" "%s: in %s has no producer (no member's out, not world.out, not produced by %s)"
                  m.m_name p dm.m_name
            end
            else if not (peer || List.mem p world_out || List.mem p d_rule_heads) then
              add "note" "I3" "%s: in %s is produced only by %s (transitional)" m.m_name p
                (if List.mem p host_out then "the host's status assertion (amendment 1b)"
                 else Printf.sprintf "%s's relay facts, until goal(S, K) (§8.4)" dm.m_name)
          end)
        m.m_shared)
    members;
  (* I4 one writer of a state pred *)
  List.iter (fun p ->
      let outs = List.filter (fun m -> List.assoc_opt p m.m_shared = Some "out") members in
      let state = List.filter (fun m -> has 'c' (roles m p)) outs in
      List.iter (fun m ->
          List.iter (fun r ->
              let c = List.exists (fun ((a : atom), k) -> a.pred = p && k = 'c') r.r_body in
              let o = List.exists (fun (a : atom) -> a.pred = p) r.r_head in
              if c && not o then begin
                if m.m_role = "direct" then
                  (* ruled (step 1c): a director's grants and goals are
                     levels it may withdraw *)
                  add "warning" "I4" "%s: rule %s withdraws its own out %s (a level the direct member may withdraw)"
                    m.m_name r.r_name p
                else
                  add "error" "I4" "%s: rule %s consumes its out %s without producing it (a state pred is conserved per rule)"
                    m.m_name r.r_name p
              end)
            m.m_rules)
        state;
      if List.length state > 1 then
        add "error" "I4" "%s: %s are all writers (consume and produce) of %s: a resource or one writer"
          p (String.concat ", " (List.map (fun m -> m.m_name) state)) p;
      if outs <> [] && List.mem p world_out then
        add "error" "I4" "%s: written by %s and by the world (world.out): world-private, or one writer"
          p (String.concat ", " (List.map (fun m -> m.m_name) outs)))
    all_shared;
  (* I5 gating (ruled, step 3b): `gating: program` — the member gates itself,
     so its rules read tick__grant for every resource it declares; `gating:
     host` (the default) — the agent holds its commands, so it never reads it *)
  List.iter (fun m ->
      let gating = match List.assoc_opt "gating" m.m_extra with
        | Some v -> str v | None -> "host" in
      let reads_grant r =
        List.exists (fun ru -> List.exists (fun ((a : atom), _) ->
            a.pred = "tick__grant"
            && (match List.rev a.terms with
                | TConst c :: _ -> c = r
                | TVar _ :: _ -> true
                | [] -> false)) ru.r_body) m.m_rules in
      let any_grant = List.exists (fun ru -> List.exists (fun ((a : atom), _) ->
          a.pred = "tick__grant") ru.r_body) m.m_rules in
      let resources = List.filter_map (fun (p, d) -> if d = "resource" then Some p else None) m.m_shared in
      match gating with
      | "program" ->
        List.iter (fun r ->
            if not (reads_grant r) then
              add "error" "I5" "%s: gating program, but no rule reads tick__grant for %s" m.m_name r)
          resources
      | "host" ->
        if m.m_role = "specialist" && any_grant then
          add "error" "I5" "%s: gating host, but its rules read tick__grant (the agent gates it)" m.m_name
      | g -> add "error" "I5" "%s: gating is host or program, not %s" m.m_name g)
    members;
  (* I5 every resource owned once *)
  (match List.assoc_opt "resources" dm.m_extra with
   | None -> add "note" "I5" "%s declares no resources: I5 not run" dm.m_name
   | Some v ->
     List.iter (fun (r, spec) ->
         let f = pairs spec in
         let count = match List.assoc_opt "count" f with
           | Some v -> int_of_string (str v) | None -> 1 in
         let free = match List.assoc_opt "free" f with Some v -> str v | None -> r in
         let held = match List.assoc_opt "held_by" f with Some v -> strs v | None -> [] in
         let tok = free :: held in
         List.iter (fun m ->
             List.iter (fun ru ->
                 let n_c = List.length (List.filter (fun ((a : atom), k) -> k = 'c' && List.mem a.pred tok) ru.r_body) in
                 let n_o = List.length (List.filter (fun (a : atom) -> List.mem a.pred tok) ru.r_head) in
                 if m.m_role <> "direct" && (n_c > 0 || n_o > 0) then
                   add "error" "I5" "%s: rule %s touches the token of %s (%s): only %s's rules may"
                     m.m_name ru.r_name r (String.concat "/" tok) dm.m_name
                 else if n_c <> n_o then
                   add "error" "I5" "%s: rule %s changes the token count of %s by %d (consumes %d, produces %d of %s)"
                     m.m_name ru.r_name r (n_o - n_c) n_c n_o (String.concat "/" tok))
               m.m_rules)
           members;
         let carries a = a = free ^ "(" ^ r ^ ")" || (free = r && a = r) in
         let n_free = List.fold_left (fun acc (a, n) -> if carries a then acc + n else acc) 0 dm.m_init in
         let n_held = List.fold_left (fun acc (a, n) ->
             if List.exists (fun h -> String.length a > String.length h
                                      && String.sub a 0 (String.length h + 1) = h ^ "(") held
             && (String.length a > String.length r
                 && (let t = "," ^ r ^ ")" in
                     let lt = String.length t and la = String.length a in
                     la >= lt && String.sub a (la - lt) lt = t))
             then acc + n else acc) 0 dm.m_init in
         if n_free <> count then
           add "error" "I5" "%s: init holds %d of the free %s token, the count is %d" dm.m_name n_free r count;
         if n_held <> 0 then
           add "error" "I5" "%s: init already holds %s (%d held atoms)" dm.m_name r n_held)
       (pairs v));
  (* I6 types agree *)
  List.iter (fun p ->
      let sigs = List.sort_uniq compare (List.filter_map (fun m ->
          match List.assoc_opt p m.m_sigs with
          | Some a when List.mem_assoc p (crossing m) -> Some (m.m_name, a)
          | _ -> None) members) in
      let distinct = List.sort_uniq compare (List.map snd sigs) in
      if List.length distinct > 1 then
        add "error" "I6" "%s has several signatures: %s" p
          (String.concat ", " (List.map (fun (n, a) ->
               Printf.sprintf "%s(%s) in %s" p (String.concat ", " a) n) sigs)))
    all_shared;
  let tnames = List.sort_uniq compare (List.concat_map (fun m -> List.map fst m.m_types) members) in
  List.iter (fun t ->
      let defs = List.sort_uniq compare (List.filter_map (fun m ->
          Option.map (List.sort_uniq compare) (List.assoc_opt t m.m_types)) members) in
      if List.length defs > 1 then
        add "error" "I6" "type %s has %d different member sets across the members" t (List.length defs))
    tnames;
  (* I7 reserved names; status atoms are outs *)
  List.iter (fun m ->
      List.iter (fun (p, f) ->
          let n = String.length p in
          let rec dunder i = i + 1 < n && ((p.[i] = '_' && p.[i + 1] = '_') || dunder (i + 1)) in
          if dunder 0 && ipath_of_file f = None then
            add "error" "I7" "%s: pred %s carries the reserved `__` (declared in %s)" m.m_name p (show f))
        m.m_decl_file;
      List.iter (fun (k, atoms) ->
          List.iter (fun a ->
              if List.assoc_opt a m.m_shared <> Some "out" then
                add "error" "I7" "%s: status %s atom %s is not one of its outs" m.m_name k a)
            atoms)
        m.m_status)
    members;
  (* I8 the include DAG; no direct naming *)
  let program_dirs = List.map (fun m -> Filename.dirname m.m_program) members in
  List.iter (fun m ->
      List.iter (fun (_, g) ->
          List.iter (fun m' ->
              if m'.m_name <> m.m_name && Filename.dirname g = Filename.dirname m'.m_program then
                add "error" "I8" "%s: includes %s, a file of member %s" m.m_name (show g) m'.m_name)
            members)
        m.m_includes)
    members;
  ignore program_dirs;
  (* ruled (step 3b): a file with rules included by several members is a
     SHARED LIFTED DOMAIN (a base several members instantiate) when it is
     no member's top file and lies in no member's package directory;
     otherwise one member reaches into another *)
  let shared_files = List.sort_uniq compare (List.concat_map (fun m -> m.m_files) members) in
  List.iter (fun f ->
      let users = List.filter (fun m -> List.mem f m.m_files) members in
      if List.length users > 1 && f <> capacity && ipath_of_file f = None then begin
        let has_rules = List.exists (fun m -> List.exists (fun r -> r.r_file = f) m.m_rules) users in
        let names = String.concat ", " (List.map (fun m -> m.m_name) users) in
        if has_rules then begin
          if List.exists (fun m -> m.m_program = f
                                   || Filename.dirname f = Filename.dirname m.m_program) members then
            add "error" "I8" "%s is included by %s and is a member's own file: only a lifted domain is shared"
              (show f) names
          else begin
            shared_bases := f :: !shared_bases;
            add "note" "I8" "%s, a lifted domain shared by %s" (show f) names
          end
        end
      end)
    shared_files;
  let names = List.map (fun m -> m.m_name) members in
  List.iter (fun m ->
      if m.m_role = "specialist" then
        List.iter (fun r ->
            List.iter (fun (a : atom) ->
                List.iter (function
                    | TConst c when c <> m.m_name && List.mem c names ->
                      add "error" "I8" "%s: rule %s names the member %s (%s): only through the protocol"
                        m.m_name r.r_name c (Ast.atom_str a)
                    | _ -> ()) a.terms)
              (List.map fst r.r_body @ r.r_head))
          m.m_rules)
    members;
  (* I9 copies are not statics *)
  List.iter (fun m ->
      List.iter (fun (p, d) ->
          if (d = "in" || d = "out") && List.mem p m.m_bwd then
            add "error" "I9" "%s: %s %s is a bwd static, not a port" m.m_name d p)
        m.m_shared;
      List.iter (fun p ->
          if List.mem p m.m_bwd then
            add "error" "I9" "%s: world.out %s is a bwd static the host would refresh" m.m_name p)
        (List.filter (fun p -> List.mem_assoc p m.m_sigs) world_out))
    members;
  (* I10 ownership; I11 natures; I12 keys *)
  List.iter (fun m ->
      List.iter (fun (p, _) ->
          match iface_owner p with
          | [] ->
            if own_decl m p then
              add "error" "I10" "%s: shared %s is declared by %s itself (%s), not by an interface package"
                m.m_name p m.m_name (show (List.assoc p m.m_decl_file))
          | [i] ->
            if not (List.mem i.i_path m.m_files) then
              add "error" "I10" "%s: shared %s belongs to %s, which %s does not include" m.m_name p i.i_name m.m_name
            else if own_decl m p then
              add "error" "I10" "%s: shared %s is declared again by %s" m.m_name p m.m_name
          | is ->
            add "error" "I10" "%s: %s is declared by several interface packages: %s" m.m_name p
              (String.concat ", " (List.map (fun i -> i.i_name) is)))
        (crossing m))
    members;
  List.iter (fun i ->
      if i.i_rules then
        add "error" "I10" "interface package %s has rules or facts: declarations only" i.i_name;
      match i.i_nature with
      | None -> add "note" "I11" "interface package %s declares no natures: I11 not run" i.i_name
      | Some nat ->
        List.iter (fun m ->
            List.iter (fun (p, d) ->
                match List.assoc_opt p nat with
                | None -> ()
                | Some n ->
                  let ok = match n, m.m_role with
                    | "signal", "specialist" -> List.mem d ["in"; "out"; "world-private"]
                    | "signal", _ -> List.mem d ["in"; "out"]
                    | "resource", "specialist" -> d = "resource"
                    | "resource", _ -> true
                    | "report", "specialist" -> d = "out"
                    | "report", _ -> d = "in"
                    | _ -> false in
                  if not ok then
                    add "error" "I11" "%s: %s %s, but %s is a %s in %s" m.m_name d p p n i.i_name)
              m.m_shared)
          members)
    ipkgs;
  let by_name = Hashtbl.create 8 in
  List.iter (fun m ->
      List.iter (fun f ->
          match ipath_of_file f with
          | Some _ -> ()
          | None ->
            (* a file named like an interface package but not the bundle's *)
            let base = Filename.basename f in
            List.iter (fun i ->
                if Filename.basename i.i_path = base && i.i_path <> f then
                  let k = (load_ipkg f).i_key in
                  if k <> i.i_key then Hashtbl.replace by_name (m.m_name, i.i_name) k)
              ipkgs)
        m.m_files)
    members;
  Hashtbl.iter (fun (mn, iname) _ ->
      add "error" "I12" "%s: its %s has a key other than the bundle's" mn iname)
    by_name;
  (* the external interfaces and the keys *)
  let ei m =
    let ifs = List.filter (fun i -> List.mem i.i_path m.m_files) ipkgs in
    String.concat "\n"
      (["metis-ei 1"; "member " ^ m.m_name]
       @ List.map (fun i -> Printf.sprintf "iface %s %s" i.i_name i.i_key) ifs
       @ List.map (fun (p, d) -> Printf.sprintf "dir %s %s" p d)
         (List.sort compare m.m_shared)
       @ List.map (fun t -> "abstract " ^ t) (List.sort_uniq compare m.m_abstract)
       @ List.map (fun (k, l) -> Printf.sprintf "status %s %s" k (String.concat " " l))
         (List.sort compare m.m_status)
       @ List.map (fun (p, _) -> "resource " ^ p)
         (List.filter (fun (_, d) -> d = "resource") (List.sort compare m.m_shared))
       (* a shared lifted domain's key (ruled): instances must agree on their base *)
       @ List.map (fun f -> Printf.sprintf "base %s %s" (Filename.basename f)
                      (Sha256.hex (Ast.pretty (Ast.strip_locs (Parser.parse_file f)))))
         (List.filter (fun f -> List.mem f m.m_files) (List.sort compare !shared_bases)))
    ^ "\n" in
  let cap_key = Sha256.hex (Ast.pretty (Ast.strip_locs (Parser.parse_file capacity))) in
  let canon_comp = String.concat "\n" (List.map (fun (k, v) ->
      let rec show = function
        | S s -> s
        | L l -> "[" ^ String.concat ", " (List.map show l) ^ "]"
        | M m -> "{" ^ String.concat ", " (List.map (fun (k, v) -> k ^ ": " ^ show v)
                                           (List.sort compare m)) ^ "}" in
      k ^ ": " ^ show v) (List.sort compare comp)) in
  let package_key = Sha256.hex (String.concat "\n"
      (["metis-package 1"]
       @ List.map (fun i -> Printf.sprintf "iface %s %s" i.i_name i.i_key) ipkgs
       @ [Printf.sprintf "capacity %s" cap_key]
       @ List.map (fun m -> Printf.sprintf "%s %s %s %s" m.m_role m.m_name m.m_key
                      (Sha256.hex (ei m))) (dm :: specs)
       @ [canon_comp]) ^ "\n") in
  (* the cut *)
  let world_ports = world_out @ world_in in
  let cut = List.sort_uniq compare
      (List.concat_map (fun m -> List.filter_map (fun (p, d) ->
           if d = "world-private" then None else Some p) m.m_shared) members) in
  let lines = ref [] in
  let line fmt = Printf.ksprintf (fun s -> lines := s :: !lines) fmt in
  line "interface %s" (Filename.basename comp_path);
  List.iter (fun i -> line "iface %s %s %s" i.i_name (show i.i_path) i.i_key) ipkgs;
  line "capacity %s %s" (show capacity) cap_key;
  List.iter (fun m ->
      line "member %s %s %s key %s ei %s" m.m_name m.m_role (show m.m_program)
        m.m_key (Sha256.hex (ei m)))
    (dm :: specs);
  line "package %s" package_key;
  (* every include, where it resolved and the key of what it resolved to:
     a key never rests on an unprinted environment *)
  (* one line per resolved FILE (two include strings may reach it), the
     first string and place that did, and every member that includes it *)
  let incs = List.fold_left (fun acc m ->
      List.fold_left (fun acc (spec, place, f) ->
          if List.exists (fun ((_, _, f'), _) -> f' = f) acc then
            List.map (fun (((_, _, f') as k), users) ->
                if f' = f && not (List.mem m.m_name users) then (k, users @ [m.m_name])
                else (k, users)) acc
          else acc @ [((place, spec, f), [m.m_name])])
        acc m.m_inc) [] (dm :: specs) in
  List.iter (fun ((place, spec, f), users) ->
      line "include %s %s %s key %s by %s" place spec (show f)
        (Sha256.hex (Ast.pretty (Ast.strip_locs (Parser.parse_file f))))
        (String.concat " " users))
    incs;
  line "cut %d" (List.length cut);
  List.iter (fun p ->
      let who d = List.filter_map (fun m ->
          match List.assoc_opt p m.m_shared with
          | Some d' when d' = d ->
            Some (m.m_name ^ (let r = roles m p in if r = "" then "" else "(" ^ r ^ ")"))
          | _ -> None) members in
      let outs = who "out" @ (if List.mem p world_out then ["world"] else [])
                 @ (if List.mem p d_rule_heads && List.assoc_opt p dm.m_shared = None then [dm.m_name ^ "(o)"] else [])
                 @ (if List.mem p d_relay then [dm.m_name ^ "(relay, transitional)"] else [])
                 @ (if List.mem p host_out then ["host(transitional)"] else []) in
      let ins = who "in" @ (if List.mem p world_in then ["world"] else []) in
      let res = who "resource" in
      let cls =
        if res <> [] then "resource"
        else if List.exists (fun m -> List.assoc_opt p m.m_shared = Some "out" && has 'c' (roles m p)) members then "state"
        else if List.exists (fun m -> List.assoc_opt p m.m_shared = Some "in" && has 'c' (roles m p)) members then "signal"
        else "reading" in
      line "  %s %s: out [%s] in [%s]%s" p cls (String.concat " " outs) (String.concat " " ins)
        (if res = [] then "" else " resource [" ^ String.concat " " res ^ "]"))
    cut;
  line "private %s" (String.concat " " (List.map (fun m ->
      let own = List.filter (fun (p, _) -> own_decl m p && not (List.mem p m.m_bwd)) m.m_decl_file in
      Printf.sprintf "%s=%d" m.m_name
        (List.length (List.filter (fun (p, _) ->
             match List.assoc_opt p m.m_shared with
             | None | Some "world-private" -> true | _ -> false) own)))
      (dm :: specs)));
  (* the call/return smell: p out of A in B, q out of B in A, neither a world port nor read by D *)
  let d_reads p = List.exists (fun r -> List.exists (fun ((a : atom), _) -> a.pred = p) r.r_body) dm.m_rules in
  List.iter (fun a ->
      List.iter (fun b ->
          if a.m_name < b.m_name then
            List.iter (fun (p, dp) ->
                List.iter (fun (q, dq) ->
                    if dp = "out" && List.assoc_opt p b.m_shared = Some "in"
                       && dq = "out" && List.assoc_opt q a.m_shared = Some "in"
                       && not (List.mem p world_ports || List.mem q world_ports)
                       && not (d_reads p || d_reads q) then
                      add "note" "smell" "%s/%s between %s and %s: a call/return pair no world port or %s reads"
                        p q a.m_name b.m_name dm.m_name)
                  (crossing b))
              (crossing a))
        members)
    members;
  let fs = List.rev !findings in
  let order s = match s with "error" -> 0 | "warning" -> 1 | _ -> 2 in
  let fs = List.stable_sort (fun x y -> compare (order x.sev) (order y.sev)) fs in
  List.iter (fun f -> line "%s %s %s" f.sev f.chk f.text) fs;
  let n s = List.length (List.filter (fun f -> f.sev = s) fs) in
  line "result %d error(s), %d warning(s), %d note(s)" (n "error") (n "warning") (n "note");
  (List.rev !lines, n "error")
