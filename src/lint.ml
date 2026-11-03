(* SPDX-License-Identifier: Apache-2.0 *)
(* The linter (spec/08 lint phase, patterns CHECKS.md §3): shape
   findings over a program that COMPILES, never gating. Mirrors metispy
   metis/lint.py line by line — the codes, their exemptions, the texts,
   the data and the order; Diag.render_text prints them alike.

   - state-dead-end: a state pred the program's own rules produce and no
     rule consumes. Exempt: protocol atoms (`__`), preds declared by an
     interface package (a path with an `iface` component), family
     members, and with a manifest its `shared` out/resource/world-private
     preds and its status atoms.
   - state-unproduced: a pred some rule reads or consumes that no rule
     produces, no `#init` holds, and nothing outside supplies (the same
     exemptions, plus `shared` in).
   - rules-twin-body: two rules of one stage with the same premises
     (variables renamed by first occurrence) and different heads.
   - report-ungated: a rule consuming an atom whose last argument is a
     generation (`tick__gen`) without reading `$tick__gen(…, G)` with the
     same variable.
   - stages-twice: an included unit states `stages` or `layers` that the
     includer also states, differently.
   - belief-in-safety: with the manifest's `safety: [stages]`, a rule of
     one of them reads or consumes a belief pred: the `belief:` list and
     the keys of the spec/16 `beliefs:` and `levels:` maps.
   - enter-equals-hold: a HOLD rule (it reads `$S`, its head is `one`: an
     act) and the ENTRY rule of S (it makes S, does not read it) both read
     a member of one declared `family`. Silent with no family.
   - name-not-a-command: with the manifest's `commands: [...]`, an act
     whose name is no entry and does not begin with an entry and `_`.
   - invariant-init (runtime phase, error): the file's `#init` holds a sum
     over an invariant's members other than the declared one. *)

open Ast

(* python's str.split() whitespace, inside one line *)
let is_ws c = c = ' ' || c = '\t' || c = '\r' || c = '\x0b' || c = '\x0c'

let lines text =
  List.map (fun l ->
      let n = String.length l in
      if n > 0 && l.[n - 1] = '\r' then String.sub l 0 (n - 1) else l)
    (String.split_on_char '\n' text)

let words l =
  let out = ref [] and cur = Buffer.create 16 in
  let flush () =
    if Buffer.length cur > 0 then begin
      out := Buffer.contents cur :: !out; Buffer.clear cur end in
  String.iter (fun c -> if is_ws c then flush () else Buffer.add_char cur c) l;
  flush ();
  List.rev !out

let all_digits s = s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s

(* the predicates the file's `#init` lines hold (metispy init_preds: the
   regex `^\s*#init\s+` then an identifier `[A-Za-z][A-Za-z0-9_-]` star) *)
let init_preds text =
  List.filter_map (fun l -> match words l with
      | "#init" :: a :: _ when (a.[0] >= 'A' && a.[0] <= 'Z') || (a.[0] >= 'a' && a.[0] <= 'z') ->
        let n = String.length a in
        let rec go i =
          if i < n && (let c = a.[i] in
                       (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                       || (c >= '0' && c <= '9') || c = '_' || c = '-')
          then go (i + 1) else i in
        Some (String.sub a 0 (go 0))
      | _ -> None)
    (lines text)

(* `#init ATOM [N]` lines as counts (metispy init_counts: the regex
   `^\s*#init\s+(.+?)(?:\s+(\d+))?\s*$`, the lazy atom ending before a
   trailing ` N`; an atom written with inner spaces (`at(e0, f0)`) is the
   same atom the shell squashes, every space taken out; the last
   assignment wins) *)
let init_counts text =
  let strip_trailing s =
    let n = ref (String.length s) in
    while !n > 0 && is_ws s.[!n - 1] do decr n done;
    String.sub s 0 !n in
  let strip_leading s =
    let n = String.length s in
    let i = ref 0 in
    while !i < n && is_ws s.[!i] do incr i done;
    String.sub s !i (n - !i) in
  let squash a = String.concat "" (String.split_on_char ' ' a) in
  List.fold_left (fun acc l ->
      let put a n =
        if List.mem_assoc a acc then List.map (fun (x, m) -> (x, if x = a then n else m)) acc
        else acc @ [ (a, n) ] in
      let t = strip_leading (strip_trailing l) in
      let k = String.length "#init" in
      if String.length t > k && String.sub t 0 k = "#init" && is_ws t.[k] then begin
        let r = strip_leading (String.sub t k (String.length t - k)) in
        if r = "" then acc
        else begin
          (* the one cut the regex allows: before the last whitespace run,
             when all after it is digits and something stands before it *)
          let n = String.length r in
          let e = ref (n - 1) in
          while !e >= 0 && r.[!e] >= '0' && r.[!e] <= '9' do decr e done;
          let digits_from = !e + 1 in
          let w = ref !e in
          while !w >= 0 && is_ws r.[!w] do decr w done;
          if digits_from < n && !w < !e && !w >= 0 then
            put (squash (String.sub r 0 (!w + 1)))
              (int_of_string (String.sub r digits_from (n - digits_from)))
          else put (squash r) 1
        end
      end else acc)
    [] (lines text)

(* (supplied, taken): preds a manifest says come from outside (in,
   world-private) and preds it says leave or are read outside (out,
   resource, world-private, the status atoms) *)
let manifest_exempt = function
  | None -> ([], [])
  | Some manifest ->
    let m = Iface.read_yaml manifest in
    let shared = match List.assoc_opt "shared" m with
      | Some (Iface.M ps) -> List.map (fun (p, d) -> (p, Iface.str d)) ps
      | _ -> [] in
    let supplied = List.filter_map (fun (p, d) ->
        if d = "in" || d = "world-private" then Some p else None) shared in
    let taken = List.filter_map (fun (p, d) ->
        if d = "out" || d = "resource" || d = "world-private" then Some p else None) shared in
    let status = match List.assoc_opt "status" m with
      | Some (Iface.M ps) -> List.concat_map (fun (_, v) -> Iface.strs v) ps
      | _ -> [] in
    (supplied, taken @ status)

(* (safety stages, belief preds, commands or None) from a manifest
   (metispy manifest_lists): belief = the `belief:` list, then the keys of
   `beliefs:` and `levels:` not already in it *)
let manifest_lists = function
  | None -> ([], [], None)
  | Some manifest ->
    let m = Iface.read_yaml manifest in
    let list k = match List.assoc_opt k m with
      | Some v -> (try Iface.strs v with _ -> []) | None -> [] in
    let keys k = match List.assoc_opt k m with
      | Some (Iface.M ps) -> List.map fst ps | _ -> [] in
    let belief = List.fold_left (fun acc p -> if List.mem p acc then acc else acc @ [ p ])
        (list "belief") (keys "beliefs" @ keys "levels") in
    let commands = match List.assoc_opt "commands" m with
      | Some v -> Some (try Iface.strs v with _ -> []) | None -> None in
    (list "safety", belief, commands)
let uniq l = List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [ x ]) [] l
let starts_with s p = String.length s >= String.length p && String.sub s 0 (String.length p) = p
let iface_file f = List.mem "iface" (String.split_on_char '/' f)

(* premises with variables renamed by first occurrence, as a sorted
   multiset (metispy _norm: the same equality) *)
type norm_elem =
  | NAtom of string * bool * string list
  | NDistinct of string * string

let norm (elems : body_elem list) =
  let names = ref [] in
  let t = function
    | TConst v -> v
    | TVar v ->
      (match List.assoc_opt v !names with
       | Some n -> n
       | None ->
         let n = Printf.sprintf "V%d" (List.length !names) in
         names := !names @ [ (v, n) ]; n) in
  let get v = match List.assoc_opt v !names with Some n -> n | None -> v in
  let out = List.map (function
      | BDistinct (a, b) -> NDistinct (get a, get b)
      | BAtom a -> NAtom (a.pred, a.persist, List.map t a.terms)) elems in
  List.sort compare out

let src (l : Ast.loc) decl ?(doc = "") line_txt =
  { Diag.s_loc = { Diag.file = l.file; line = l.line; col = l.col; decl };
    s_subject =
      (if doc = "" then []
       else List.filter_map (fun x -> if x = "" then None else Some ("%% " ^ x))
           (String.split_on_char '\n' doc))
      @ [ line_txt ];
    s_context = []; s_layers = "" }

let sorted_set l = List.sort_uniq compare l

(* stages-twice, across the file's includes (metispy _stages_twice) *)
let rec stages_twice path seen out =
  if List.mem path !seen then ()
  else begin
    seen := path :: !seen;
    match Parser.parse_file path with
    | exception _ -> ()
    | cat ->
      List.iter2 (fun d (l : Ast.loc) -> match d with
          | DInclude (p, _) ->
            (match
               let sub = Compile.include_path p (Filename.dirname path) in
               (sub, Parser.parse_file sub)
             with
             | exception _ -> ()
             | (sub, inc) ->
               List.iter (fun (what, mine, theirs) ->
                   if mine <> [] && theirs <> [] && mine <> theirs then begin
                     let where = Filename.basename sub in
                     out := !out @ [ Diag.make "stages-twice"
                                       (Printf.sprintf "%s (%s) stated here and (%s) in %s: the first wins"
                                          what (String.concat " " mine) (String.concat " " theirs) where)
                                       (src l ("include/" ^ p) (decl_line d))
                                       [ ("decl", what); ("where", where) ] ]
                   end)
                 [ ("stages", cat.cstages, inc.cstages); ("layers", cat.clayers, inc.clayers) ];
               stages_twice sub seen out)
          | _ -> ())
        cat.cdecls cat.cdecl_locs
  end

let lint (cat : Ast.catalog) (k : Catalog.t) ~text ?manifest ?path () =
  let out = ref [] in
  let add d = out := !out @ [ d ] in
  let (supplied, taken) = manifest_exempt manifest in
  let inits = init_preds text in
  let bwd = k.Catalog.k_bwd in
  let family_members = List.concat_map snd k.Catalog.k_families in
  let decl_locs = List.combine cat.cdecls cat.cdecl_locs in
  (* name -> args, the last declaration winning (metispy's dict) *)
  let sigs = Hashtbl.create 32 in
  List.iter (function
      | DPred (n, args, _) | DBwd (n, args) -> Hashtbl.replace sigs n args
      | _ -> ()) cat.cdecls;
  let iface = List.filter_map (fun (d, (l : Ast.loc)) -> match d with
      | DPred (n, _, _) when iface_file l.file -> Some n | _ -> None) decl_locs in
  (* preds in declaration order (first occurrence), each with its decl *)
  let decl_of = List.fold_left (fun acc (d, l) -> match d with
      | DPred (n, _, _) ->
        if List.mem_assoc n acc then List.map (fun (m, x) -> (m, if m = n then (d, l) else x)) acc
        else acc @ [ (n, (d, l)) ]
      | _ -> acc) [] decl_locs in
  let produced = Hashtbl.create 32 and consumed = Hashtbl.create 32
  and read = Hashtbl.create 32 in
  let push tbl p name =
    Hashtbl.replace tbl p ((match Hashtbl.find_opt tbl p with Some l -> l | None -> []) @ [ name ]) in
  let names tbl p = match Hashtbl.find_opt tbl p with Some l -> l | None -> [] in
  (* every rule and link in source order: stage, name, the rule's body
     (atoms and <>), its body atoms, its head, its line, doc, loc *)
  let clauses = List.concat_map (fun (d, (l : Ast.loc)) -> match d with
      | DStage s ->
        List.map (fun r ->
            (s.sname, r.rname, r.rbody,
             List.filter_map (function BAtom a -> Some a | BDistinct _ -> None) r.rbody,
             r.rhead, rule_line r, r.rdoc, r.rloc)) s.srules
      | DLink ln ->
        [ ("qui", ln.lname, List.map (fun a -> BAtom a) ln.lpre_atoms, ln.lpre_atoms,
           ln.lpost_atoms, decl_line d, ln.ldoc, l) ]
      | _ -> []) decl_locs in
  List.iter (fun (_, name, _, body, head, _, _, _) ->
      List.iter (fun (a : atom) ->
          if not (List.mem a.pred bwd) then
            push (if a.persist then read else consumed) a.pred name) body;
      List.iter (fun (a : atom) ->
          if a.pred <> "one" then push produced a.pred name) head)
    clauses;
  let exempt p =
    (let n = String.length p in
     let rec has i = i + 1 < n && ((p.[i] = '_' && p.[i + 1] = '_') || has (i + 1)) in
     has 0)
    || List.mem p iface || List.mem p family_members in
  (* state-dead-end / state-unproduced, in declaration order *)
  List.iter (fun (name, (d, l)) ->
      if not (exempt name) then begin
        if Hashtbl.mem produced name && not (Hashtbl.mem consumed name)
           && not (List.mem name taken) then begin
          let producers = sorted_set (names produced name) in
          add (Diag.make "state-dead-end"
                 (Printf.sprintf "%s: produced by %s and consumed by no rule: a hold with no way on"
                    name (String.concat ", " producers))
                 (src l ("pred/" ^ name) (decl_line d))
                 [ ("pred", name); ("producers", String.concat " " producers) ])
        end;
        let users = sorted_set (names consumed name @ names read name) in
        if users <> [] && not (Hashtbl.mem produced name) && not (List.mem name inits)
           && not (List.mem name supplied) then
          add (Diag.make "state-unproduced"
                 (Printf.sprintf "%s: read by %s and produced by no rule, #init or manifest"
                    name (String.concat ", " users))
                 (src l ("pred/" ^ name) (decl_line d))
                 [ ("pred", name); ("readers", String.concat " " users) ])
      end)
    decl_of;
  (* rules-twin-body, per stage: the first rule of a body is the twin
     of every later one with another head *)
  let seen = Hashtbl.create 32 in
  List.iter (fun (stage, name, rbody, _, head, line, doc, l) ->
      if stage <> "qui" then begin
        let key = (stage, norm rbody) in
        match Hashtbl.find_opt seen key with
        | Some (first, fhead) when norm (List.map (fun a -> BAtom a) head) <> fhead ->
          add (Diag.make "rules-twin-body"
                 (Printf.sprintf "%s: the same premises as %s with another head: twin bodies the sampler weighs apart"
                    name first)
                 (src l (stage ^ "/" ^ name) ~doc line)
                 [ ("rule", name); ("twin", first) ])
        | Some _ -> ()
        | None -> Hashtbl.add seen key (name, norm (List.map (fun a -> BAtom a) head))
      end)
    clauses;
  (* report-ungated *)
  List.iter (fun (stage, name, _, body, _, line, doc, l) ->
      let last_var (a : atom) = match List.rev a.terms with
        | TVar v :: _ -> Some v | _ -> None in
      let gens = List.filter (fun (a : atom) ->
          (not a.persist) && a.pred <> "tick__gen"
          && (match Hashtbl.find_opt sigs a.pred with
              | Some (_ :: _ as args) -> List.nth args (List.length args - 1) = "tick__gen"
              | _ -> false)
          && last_var a <> None) body in
      if gens <> [] then begin
        let guarded = List.filter_map (fun (a : atom) ->
            if a.pred = "tick__gen" then last_var a else None) body in
        List.iter (fun (a : atom) ->
            match last_var a with
            | Some v when not (List.mem v guarded) ->
              add (Diag.make "report-ungated"
                     (Printf.sprintf "%s: consumes %s without reading $tick__gen for its generation %s"
                        name a.pred v)
                     (src l (stage ^ "/" ^ name) ~doc line)
                     [ ("rule", name); ("pred", a.pred) ])
            | _ -> ()) gens
      end)
    clauses;
  let (safety, belief, commands) = manifest_lists manifest in
  (* belief-in-safety *)
  List.iter (fun (stage, name, _, body, _, line, doc, l) ->
      if List.mem stage safety then
        List.iter (fun p ->
            add (Diag.make "belief-in-safety"
                   (Printf.sprintf "%s: a safety-stage rule reads the belief %s" name p)
                   (src l (stage ^ "/" ^ name) ~doc line)
                   [ ("rule", name); ("pred", p); ("stage", stage) ]))
          (uniq (List.filter_map (fun (a : atom) ->
               if List.mem a.pred belief then Some a.pred else None) body)))
    clauses;
  (* enter-equals-hold *)
  let in_family p = List.exists (fun (_, ms) -> List.mem p ms) k.Catalog.k_families in
  let acts = List.filter (fun (stage, _, _, _, head, _, _, _) ->
      stage <> "qui" && List.for_all (fun (a : atom) -> a.pred = "one") head) clauses in
  List.iter (fun (stage, name, _, body, _, line, doc, l) ->
      let preds = uniq (List.map (fun (a : atom) -> a.pred) body) in
      List.iter (fun s ->
          List.iter (fun (_, ename, _, ebody, ehead, _, _, _) ->
              let theirs = List.map (fun (a : atom) -> a.pred) ebody in
              if List.exists (fun (a : atom) -> a.pred = s) ehead && not (List.mem s theirs) then
                List.iter (fun c ->
                    if c <> s && List.mem c theirs && in_family c then
                      add (Diag.make "enter-equals-hold"
                             (Printf.sprintf "%s holds %s on %s, which %s tests to enter %s: the act can move %s, so the hold lets go mid-act"
                                name s c ename s c)
                             (src l (stage ^ "/" ^ name) ~doc line)
                             [ ("rule", name); ("entry", ename); ("state", s); ("cls", c) ]))
                  preds)
            clauses)
        (uniq (List.filter_map (fun (a : atom) ->
             if a.persist && not (List.mem a.pred bwd) then Some a.pred else None) body)))
    acts;
  (* name-not-a-command *)
  (match commands with
   | None -> ()
   | Some cmds ->
     List.iter (fun (stage, name, _, _, _, line, doc, l) ->
         if not (List.exists (fun e -> name = e || starts_with name (e ^ "_")) cmds) then
           add (Diag.make "name-not-a-command"
                  (Printf.sprintf "%s: acts by its name, and no command the host takes begins it: the rule fires and nothing moves" name)
                  (src l (stage ^ "/" ^ name) ~doc line)
                  [ ("rule", name) ]))
       acts);
  (* stages-twice, across the file's includes *)
  (match path with
   | Some p -> stages_twice p (ref []) out
   | None -> ());
  !out

let invariant_init (k : Catalog.t) counts =
  List.filter_map (fun (name, members, total) ->
      let held = List.fold_left (fun acc (atom, n) ->
          let pred = match String.index_opt atom '(' with
            | Some i -> String.sub atom 0 i | None -> atom in
          if List.mem pred members then acc + n else acc) 0 counts in
      if held <> total then
        Some (Diag.make "invariant-init"
                (Printf.sprintf "invariant %s: the state holds %d token(s) over %s, declared %d"
                   name held (String.concat " " members) total)
                { Diag.s_loc = { Diag.file = ""; line = 0; col = 0; decl = "invariant/" ^ name };
                  s_subject = [ Printf.sprintf "invariant %s (%s) : %d." name (String.concat " " members) total ];
                  s_context = []; s_layers = "" }
                [ ("invariant", name); ("members", String.concat " " members);
                  ("total", string_of_int total); ("held", string_of_int held) ])
      else None)
    k.Catalog.k_invariants
