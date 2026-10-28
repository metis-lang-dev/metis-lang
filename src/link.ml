(* SPDX-License-Identifier: Apache-2.0 *)
(* spec/17 §4 — the link step. See link.mli. *)

open Iface

type opts = { out : string option; check : bool; tar : bool; bundles : string option; build : bool }

(* the tree director's hysteresis (the road's: k = 2 grant ages young, m = 1
   status age; policy-tuning-2 2a's compose.py, spec 15 §9 rule 4) *)
let ages = ["a0"; "a1"; "a2"; "a3"]
let hold_grant = 2
let hold_status = 1

let uniq l = List.sort_uniq compare l
let minus a b = List.filter (fun x -> not (List.mem x b)) a
let opt_assoc k l = List.assoc_opt k l

(* -- the derived director (§3.3) ------------------------------------- *)

type derived = {
  planner : string option;
  dspecs : string list;                    (* the specialist(S) facts *)
  handles : (string * string) list;        (* (domain, kind) *)
  results : string list; ends : string list; finished : string list; nohandler : string list;
  detour : (string * string) list; escalate : (string * string) list;
  rename : (string * string * string) list;
  priority : (string * string) list;
  resources : (string * int) list;
  kinds : string list;
  planner_err : string option }

(* a member's kinds: its shared in/out preds that are neither the protocol's
   nor a resource nor world-private *)
let kinds_of proto m d =
  List.filter_map (fun (p, d') -> if d' = d && not (List.mem p proto) then Some p else None) m.m_shared

let status_of m k = Option.value (List.assoc_opt k m.m_status) ~default:[]

let pairs_of_y v =
  List.map (function
      | L [a; b] -> (str a, str b)
      | _ -> raise (Yaml_error "a pair [A, B] expected")) (match v with L l -> l | _ -> [])

let derive ~comp ~proto ~world_out ~(specs : member list) ~(hand : member option) =
  let ins m = kinds_of proto m "in" and outs m = kinds_of proto m "out" in
  let all_out = uniq (List.concat_map outs specs) and all_in = uniq (List.concat_map ins specs) in
  let cross = List.filter (fun k -> List.mem k all_in) all_out in
  let (planner, planner_err) = match opt_assoc "planner" comp with
    | Some v ->
      let p = str v in
      if List.exists (fun m -> m.m_name = p) specs then (Some p, None)
      else (None, Some (Printf.sprintf "planner: %s is not a specialist" p))
    | None when cross = [] -> (None, None)        (* nothing crosses: no routing, no planner (the road, kitchen_pot) *)
    | None ->
      (* the one member that consumes every kind the others produce and some member consumes *)
      let cands = List.filter (fun m ->
          let others = uniq (List.concat_map outs (List.filter (fun x -> x.m_name <> m.m_name) specs)) in
          List.for_all (fun k -> List.mem k (ins m)) (List.filter (fun k -> List.mem k all_in) others))
          specs in
      (match cands with
       | [m] -> (Some m.m_name, None)
       | [] -> (None, Some "no member consumes every result kind: name one with planner:")
       | l -> (None, Some ("more than one candidate (" ^ String.concat ", " (List.map (fun m -> m.m_name) l)
                          ^ "): name one with planner:"))) in
  let pm = Option.bind planner (fun p -> List.find_opt (fun m -> m.m_name = p) specs) in
  let dspec_ms = List.filter (fun m -> Some m.m_name <> planner) specs in
  let spec_outs = uniq (List.concat_map outs dspec_ms) in
  (* a specialist handles its goal kinds: what it consumes that no specialist and no world reading produces —
     the planner's goals and the routing block's targets; a result is never routed to a specialist *)
  let handles_s = List.concat_map (fun m ->
      List.map (fun k -> (m.m_name, k))
        (List.filter (fun k -> not (List.mem k spec_outs) && not (List.mem k world_out)) (uniq (ins m))))
      (if planner = None then [] else dspec_ms) in
  let handles_p = match pm with Some m -> List.map (fun k -> (m.m_name, k)) (uniq (ins m)) | None -> [] in
  let results = match pm with
    | Some m -> List.filter (fun k -> List.mem k (ins m)) (uniq (List.concat_map (fun s -> status_of s "success") dspec_ms))
    | None -> [] in
  let ends = match pm with Some m -> status_of m "failure" | None -> [] in
  let finished = match pm with Some m -> status_of m "success" | None -> [] in
  let nohandler = match pm with
    | Some m -> List.filter (fun k -> not (List.mem k all_in) && not (List.mem k (ends @ finished))) (uniq (outs m))
    | None -> [] in
  let routing = match opt_assoc "routing" comp with Some v -> pairs v | None -> [] in
  let two k = match opt_assoc k routing with Some v -> pairs_of_y v | None -> [] in
  let rename = match opt_assoc "rename" routing with
    | Some (L l) -> List.map (function L [a; b; c] -> (str a, str b, str c)
                                     | _ -> raise (Yaml_error "rename: [K1, K2, G] expected")) l
    | _ -> [] in
  let fact_pairs name = match hand with
    | None -> []
    | Some h -> List.filter_map (fun (a : Ast.atom) ->
        match a.pred, a.terms with
        | n, [Ast.TConst x; Ast.TConst y] when n = name -> Some (x, y)
        | _ -> None) h.m_facts in
  let priority = match opt_assoc "priority" comp with
    | Some v -> pairs_of_y v
    | None -> fact_pairs "priority" in
  let resources =
    let from_comp = match opt_assoc "resources" comp with
      | Some v -> List.map (fun (r, n) -> (r, int_of_string (str n))) (pairs v) | None -> [] in
    let from_hand = match hand with
      | Some h -> (match List.assoc_opt "resources" h.m_extra with
          | Some v -> List.map (fun (r, spec) ->
              (r, match spec with M kv -> (match List.assoc_opt "count" kv with Some n -> int_of_string (str n) | None -> 1)
                                | _ -> 1)) (pairs v)
          | None -> [])
      | None -> [] in
    let from_specs = uniq (List.concat_map (fun m ->
        List.filter_map (fun (p, d) -> if d = "resource" then Some p else None) m.m_shared) specs) in
    if from_comp <> [] then from_comp else if from_hand <> [] then from_hand
    else List.map (fun r -> (r, 1)) from_specs in
  let detour = two "detour" and escalate = two "escalate" in
  let kinds = uniq (List.map snd handles_s @ List.map snd handles_p @ results @ ends @ finished @ nohandler
                    @ List.concat_map (fun (a, b) -> [a; b]) (detour @ escalate)
                    @ List.concat_map (fun (a, b, c) -> [a; b; c]) rename) in
  { planner; dspecs = List.map (fun m -> m.m_name) (if planner = None then specs else dspec_ms);
    handles = handles_s @ handles_p; results; ends; finished; nohandler; detour; escalate; rename;
    priority; resources; kinds = (if kinds = [] || planner = None then ["none"] else kinds); planner_err }

let director_facts d =
  List.map (fun s -> Printf.sprintf "specialist(%s)." s) d.dspecs
  @ (match d.planner with Some p -> [Printf.sprintf "planner(%s)." p] | None -> [])
  @ List.map (fun (s, k) -> Printf.sprintf "handles(%s, %s)." s k) d.handles
  @ List.map (Printf.sprintf "result(%s).") d.results
  @ List.map (Printf.sprintf "end(%s).") d.ends
  @ List.map (Printf.sprintf "finished(%s).") d.finished
  @ List.map (Printf.sprintf "nohandler(%s).") d.nohandler
  @ List.map (fun (a, b) -> Printf.sprintf "detour(%s, %s)." a b) d.detour
  @ List.map (fun (a, b) -> Printf.sprintf "escalate(%s, %s)." a b) d.escalate
  @ List.map (fun (a, b, c) -> Printf.sprintf "rename(%s, %s, %s)." a b c) d.rename
  @ List.map (fun (a, b) -> Printf.sprintf "priority(%s, %s)." a b) d.priority

(* the generated director's program: the toolchain's lifted bases, by name (METIS_HOME's iface/), the capacity
   copied beside it (so the source and its hash do not depend on where the image is written), the facts, the
   tree director's starting state *)
let director_llp ?types name d =
  let route = d.planner <> None in
  let young = List.filteri (fun i _ -> i < hold_grant) ages and mature = List.filteri (fun i _ -> i >= hold_grant) ages in
  let off = d.dspecs in
  String.concat "\n"
    ([Printf.sprintf "%% %s — the composition's direct member, GENERATED by metisc --link (spec/17 §3.3). Never edited." name;
      Printf.sprintf "catalog %s 1." name;
      "provenance text \"generated at link from the composition's ports (spec/17 §3.3)\" \"2026-10-28\"."]
     @ (if route then ["include \"iface/director_domain.llp\"."] else [])
     @ ["include \"iface/director_tree_domain.llp\"."]
     @ (if route then ["include \"iface/director_tree_wake.llp\"."] else [])
     @ (match types with
         | None -> ["include \"capacity.llp\"."; ""]
         | Some (doms, rs) ->      (* the capacity is a role vocabulary (alfworld): the two types, as L13 checked them *)
           [Printf.sprintf "type domain {%s}." (String.concat " " doms)]
           @ (if rs = [] then [] else [Printf.sprintf "type resource {%s}." (String.concat " " rs)]) @ [""])
     @ [Printf.sprintf "type kind {%s}." (String.concat " " d.kinds)]
     @ (if route then [] else ["bwd specialist(domain)."])
     @ director_facts d
     @ List.map (Printf.sprintf "young_grant(%s).") young @ List.map (Printf.sprintf "mature_grant(%s).") mature
     @ List.map (Printf.sprintf "mature_status(%s).") (List.filteri (fun i _ -> i >= hold_status) ages)
     @ [""]
     @ (match d.planner with
         | Some p -> [Printf.sprintf "#init active(%s) 1" p; Printf.sprintf "#init attention(%s) 1" p; "#init fresh 1"]
                     @ List.map (Printf.sprintf "#init inactive(%s) 1") d.dspecs
                     @ [Printf.sprintf "#init path(%s) 1" p; Printf.sprintf "#init tick__goal(%s) 1" p]
         | None -> [])
     @ List.map (fun (r, n) -> Printf.sprintf "#init free(%s) %d" r n) d.resources
     @ List.map (Printf.sprintf "#init offpath(%s) 1") off @ List.map (Printf.sprintf "#init nowant(%s) 1") off
     @ List.map (Printf.sprintf "#init nolate(%s) 1") off
     @ List.map (fun m -> Printf.sprintf "#init age_of(%s, a0) 1" m) (d.dspecs @ Option.to_list d.planner)
     @ List.map (fun (r, _) -> Printf.sprintf "#init issue(%s, t0) 1" r) d.resources
     @ List.map (fun (r, _) -> Printf.sprintf "#init serving(%s, t0) 1" r) d.resources
     @ ["#steps 6"; "#seeds 1"]) ^ "\n"

let director_manifest name d =
  String.concat "\n"
    [Printf.sprintf "# %s — GENERATED by metisc --link (spec/17 §3.3)" name;
     Printf.sprintf "program: %s.llp" name;
     "clock: {beats: 1}";
     "voice: line";
     "shared: {tick__want: in, tick__release: in, tick__status: in, tick__active: in, tick__done: in, tick__stuck: in, \
      tick__grant: out, tick__revoke: out, tick__goal: out, tick__cancel: out, tick__stop: in}";
     Printf.sprintf "resources: {%s}"
       (String.concat ", " (List.map (fun (r, n) -> Printf.sprintf "%s: {count: %d, free: free, held_by: [holder]}" r n)
                              d.resources))] ^ "\n"

(* -- the link ---------------------------------------------------------- *)

let manifest_s m k = match List.assoc_opt k m.m_extra with Some (S s) -> Some s | _ -> None

let run ~wire o comp_path =
  let comp_dir = Filename.dirname (norm comp_path) in
  let comp = read_yaml comp_path in
  let direct = str (match List.assoc_opt "direct" comp with Some v -> v
                                                            | None -> raise (Yaml_error "no direct")) in
  let world_out = match List.assoc_opt "world" comp with
    | Some w -> (match List.assoc_opt "out" (pairs w) with Some v -> strs v | None -> []) | None -> [] in
  let hand_dir = Filename.concat comp_dir direct in
  let hand = Sys.file_exists (Filename.concat hand_dir "domain.yaml") in
  (* the derivation needs the specialists: loaded as the check loads them *)
  let specs0 = List.map (fun n -> load_member comp_dir n "specialist") (strs (List.assoc "specialists" comp)) in
  let proto_path = match List.assoc_opt "protocol" comp with
    | Some v -> Some (snd (Compile.include_place (str v) comp_dir)) | None -> None in
  let proto_preds = match proto_path with
    | Some f -> List.filter_map (function Ast.DPred (n, _, _) | Ast.DBwd (n, _) -> Some n | _ -> None)
                  (Parser.parse_file f).Ast.cdecls
    | None -> [] in
  let proto = uniq (proto_preds @ List.filter (fun p -> String.length p > 6 && String.sub p 0 6 = "tick__")
                                     (List.concat_map (fun m -> List.map fst m.m_shared) specs0)) in
  let hand_m = if hand then Some (load_member comp_dir direct "direct") else None in
  let d = derive ~comp ~proto ~world_out ~specs:specs0 ~hand:hand_m in
  let capacity = snd (Compile.include_place (str (List.assoc "capacity" comp)) comp_dir) in
  (* the generated director's package: staged under the build directory *)
  let build = match o.out with Some b -> b | None -> Filename.concat comp_dir "build" in
  let stage = let f = Filename.temp_file "metisc-link-" "" in Sys.remove f; f in
  let cap_text = Image.read_file capacity in
  let cap_has_domain = List.exists (function Ast.DType ("domain", _) -> true | _ -> false)
      (Parser.parse_file capacity).Ast.cdecls in
  let types = if cap_has_domain then None
    else Some (List.map (fun m -> m.m_name) specs0, List.map fst d.resources) in
  let gen_llp = director_llp ?types direct d and gen_man = director_manifest direct d in
  let stage_dir = Filename.concat stage direct in
  Image.mkdir_p stage_dir;
  Image.write_file (Filename.concat stage_dir (direct ^ ".llp")) gen_llp;
  Image.write_file (Filename.concat stage_dir "domain.yaml") gen_man;
  if types = None then Image.write_file (Filename.concat stage_dir "capacity.llp") cap_text;
  let a = if hand then analyse comp_path else analyse ~direct_dir:stage comp_path in
  let members = a.a_members in
  let specs = List.filter (fun m -> m.m_role = "specialist") members in
  let dm = List.find (fun m -> m.m_role = "direct") members in
  let lines = ref [] in
  let line fmt = Printf.ksprintf (fun s -> lines := s :: !lines) fmt in
  let fs = ref [] in
  let add sev chk fmt = Printf.ksprintf (fun text -> fs := { sev; chk; text } :: !fs) fmt in
  let specialists = a.a_specialists in
  (* L13 members and types *)
  let cap_ast = Parser.parse_file capacity in
  let cap_type n =
    match List.find_map (function Ast.DType (t, cs) when t = n -> Some cs | _ -> None) cap_ast.Ast.cdecls with
    | Some cs -> Some cs
    | None -> List.find_map (fun m -> List.assoc_opt n m.m_types) specs in   (* tick_types beside a role capacity *)
  (match cap_type "domain" with
   | Some ds when uniq ds = uniq specialists -> ()
   | Some ds -> add "error" "L13" "link-types: the capacity's type domain {%s} is not the specialists {%s}"
                  (String.concat " " ds) (String.concat " " specialists)
   | None -> add "error" "L13" "link-types: the capacity declares no type domain");
  (match cap_type "resource" with
   | Some rs when uniq rs = uniq (List.map fst d.resources) -> ()
   | Some rs -> add "error" "L13" "link-types: the capacity's type resource {%s} is not the resources the direct member owns {%s}"
                  (String.concat " " rs) (String.concat " " (List.map fst d.resources))
   | None when d.resources = [] -> ()
   | None -> add "error" "L13" "link-types: the capacity declares no type resource");
  (* L14 capacity, L24 protocol: each member's include closure has them (the hand director: transitional, warned) *)
  List.iter (fun m ->
      let sev = if m.m_role = "direct" && hand then "warning" else "error" in
      if not (List.mem capacity m.m_files) && m.m_role <> "direct" then
        add sev "L14" "link-capacity: %s does not include the capacity %s" m.m_name (rel comp_dir capacity);
      match proto_path with
      | Some pf when not (List.mem (norm pf) m.m_files) ->
        add sev "L24" "link-protocol: %s does not include the composition's protocol" m.m_name
      | _ -> ()) members;
  (* L15 priority: a strict partial order over the specialists, transitively closed *)
  let pri = d.priority in
  List.iter (fun (p, q) ->
      if p = q then add "error" "L15" "link-priority: priority(%s, %s) is a self pair" p q;
      List.iter (fun x -> if not (List.mem x specialists) then
                    add "error" "L15" "link-priority: %s is not a specialist" x) [p; q]) pri;
  let rec closure c =
    let c' = uniq (c @ List.concat_map (fun (a, b) -> List.filter_map (fun (b', e) ->
        if b = b' then Some (a, e) else None) c) c) in
    if List.length c' = List.length c then c else closure c' in
  let closed = closure (uniq pri) in
  List.iter (fun (p, q) -> if p = q then add "error" "L15" "link-priority: a cycle through %s" p)
    (uniq (List.filter (fun (p, q) -> p = q) closed));
  (* L16 world.in: produced by a member (a rule of that name, or a head atom), consumed by none *)
  List.iter (fun p ->
      let pre = p ^ "_" in
      let verb n = n = p || (String.length n > String.length pre && String.sub n 0 (String.length pre) = pre) in
      let produced = List.exists (fun m -> List.exists (fun r ->
          verb r.r_name || List.exists (fun (h : Ast.atom) -> h.pred = p) r.r_head) m.m_rules) members in
      (* a command verb may also be a goal kind between members (alfworld's take(O): the planner's out, grasp's in)
         or a routing target (minihack's open: detour(closed, open)); consumed FROM THE WORLD only otherwise *)
      let member_out = List.exists (fun m -> List.assoc_opt p m.m_shared = Some "out") members in
      let routed = List.mem p (List.map snd d.detour @ List.map (fun (_, b, _) -> b) d.rename) in
      let consumed = if member_out || routed then []
        else List.filter (fun m -> List.assoc_opt p m.m_shared = Some "in") members in
      if not produced then add "error" "L16" "link-world-in: %s is produced by no member" p;
      if consumed <> [] then add "error" "L16" "link-world-in: %s is consumed by %s" p
          (String.concat ", " (List.map (fun m -> m.m_name) consumed)))
    a.a_world_in;
  (* L17 roles: a hand director's facts against the derived ones *)
  (match hand_m with
   | None -> ()
   | Some h ->
     add "warning" "L17" "a hand-written direct: %s (transitional); the image runs it, generated: false" direct;
     let hand_facts name = uniq (List.filter_map (fun (f : Ast.atom) ->
         if f.pred = name then Some (Ast.atom_str f) else None) h.m_facts) in
     let mine name = uniq (List.filter (fun s -> String.length s > String.length name
                                                  && String.sub s 0 (String.length name + 1) = name ^ "(")
                             (List.map (fun s -> String.sub s 0 (String.length s - 1)) (director_facts d))) in
     let norm_f s = String.concat "" (String.split_on_char ' ' s) in
     List.iter (fun (name, sev) ->
         let hf = List.map norm_f (hand_facts name) and df = List.map norm_f (mine name) in
         List.iter (fun f -> add sev "L17" "link-roles: the hand director has %s, the derivation does not" f) (minus hf df);
         List.iter (fun f -> add sev "L17" "link-roles: the derivation has %s, the hand director does not" f) (minus df hf))
       [("specialist", "error"); ("handles", "error"); ("result", "error"); ("planner", "warning"); ("end", "warning");
        ("finished", "warning"); ("nohandler", "warning"); ("detour", "warning"); ("escalate", "warning");
        ("rename", "warning"); ("priority", "warning")]);
  (* L18 clocks *)
  let rho = match List.assoc_opt "response" comp with Some v -> Some (int_of_string (str v)) | None -> None in
  if rho = None then add "warning" "L18" "no response: linked with rho = infinity";
  (* rho is in TICKS (want -> latched grant), a period in world turns a tick (spec 15 §2.3: the period multiplies
     rho in turns), so the check is on ticks: rho covers the tree director's own latency (2: want at t, preempt
     at t+1, latch at t+2); a plan's transport budget adds to it (step 5). Each member's response in turns,
     rho x period, is recorded. *)
  (match rho with
   | Some r when r < 2 -> add "error" "L18" "link-response: response %d is under the tree director's latency of 2 ticks" r
   | _ -> ());
  (* L20 places: METIS_HOME set; one include name, one file *)
  if Sys.getenv_opt "METIS_HOME" = None then add "error" "L20" "link-places: METIS_HOME is unset (the lock must say where the protocol came from)";
  let incs = List.concat_map (fun m -> List.map (fun (s, _, f) -> (s, f)) m.m_inc) members in
  List.iter (fun s ->
      let files = uniq (List.filter_map (fun (s', f) -> if s' = s then Some f else None) incs) in
      if List.length files > 1 then
        add "error" "L20" "link-places: include \"%s\" resolves to %d files across the members" s (List.length files))
    (uniq (List.map fst incs));
  (* L21 hosts: a manifest's or the composition's (amendment 1) binding, file:symbol with the file present *)
  let hosts = match List.assoc_opt "hosts" comp with Some v -> pairs v | None -> [] in
  let host_of m =
    match List.assoc_opt m.m_name hosts with
    | Some (S s) -> Some ([("py", s)], "composition")
    | Some (M kv) -> Some (List.map (fun (k, v) -> (k, str v)) kv, "composition")
    | _ -> (match manifest_s m "host" with Some s -> Some ([("py", s)], "manifest") | None -> None) in
  let host_missing m = match host_of m with
    | Some (b, origin) -> (match List.assoc_opt "py" b with
        | Some s -> (match String.index_opt s ':' with
            | Some i -> let base = if origin = "composition" then comp_dir else Filename.dirname m.m_program in
              not (Sys.file_exists (Filename.concat base (String.sub s 0 i)))
            | None -> false)
        | None -> false)
    | None -> false in
  List.iter (fun m ->
      match host_of m with
      | Some (b, origin) ->
        (match List.assoc_opt "py" b with
         | Some s -> (match String.index_opt s ':' with
             | Some i ->
               let f = String.sub s 0 i in
               let base = if origin = "composition" then comp_dir else Filename.dirname m.m_program in
               if not (Sys.file_exists (Filename.concat base f)) then
                 add "warning" "L21" "%s's host %s: no file %s beside it (the runtime that loads it must have it)" m.m_name s f
             | None -> add "error" "L21" "link-host: %s's host %s is not file:symbol" m.m_name s)
         | None -> ())
      | None -> ()) members;
  (* L22 beliefs never cross *)
  let yfield m k = match List.assoc_opt k m.m_extra with Some (M kv) -> kv | _ -> [] in
  List.iter (fun m ->
      List.iter (fun (b, _) -> match List.assoc_opt b m.m_shared with
          | Some ("in" | "out" | "resource") ->
            add "error" "L22" "link-belief-shared: %s shares its belief pred %s" m.m_name b
          | _ -> ()) (yfield m "beliefs")) members;
  (* the wires (each member's, the generated director's from the stage) *)
  (* `metisc build`: the last build's record, OUT/<name>.build ("image DIR", "member NAME SOURCE PROGRAM") *)
  let name = match List.assoc_opt "name" comp with Some v -> str v | None -> Filename.basename comp_dir in
  let record = Filename.concat build (name ^ ".build") in
  let last = if o.build && Sys.file_exists record then
      List.filter_map (fun l -> match String.split_on_char ' ' l with
          | ["image"; dir] -> Some ("", (dir, ""))
          | ["member"; m; src; pk] -> Some (m, (src, pk)) | _ -> None)
        (String.split_on_char '\n' (Image.read_file record))
    else [] in
  let last_dir = Option.map fst (List.assoc_opt "" last) in
  let reused = ref [] in
  (* the build key: the source key AND the program's '#' directives (#init, #steps: compiler-invisible, yet in the wire) *)
  let build_key m =
    let dirs = List.filter (fun l -> String.length l > 0 && l.[0] = '#')
        (List.map String.trim (String.split_on_char '\n' (Image.read_file m.m_program))) in
    Sha256.hex (m.m_key ^ "\n" ^ String.concat "\n" dirs) in
  let cached m = match last_dir, List.assoc_opt m.m_name last with
    | Some dir, Some (src, pk) when src = build_key m ->
      let f = Filename.concat build (Filename.concat dir ("members/" ^ m.m_name ^ "/ground.wire")) in
      if Sys.file_exists f then begin
        reused := m.m_name :: !reused;
        Some (List.filter (( <> ) "") (String.split_on_char '\n' (Image.read_file f)), pk)
      end else None
    | _ -> None in
  let compile m = try Ok (wire m.m_program) with
    | Catalog.Catalog_error ms | Compile.Lang_error ms -> Error (String.concat "; " ms)
    | e -> Error (Printexc.to_string e) in
  let wires = List.map (fun m -> (m.m_name, match cached m with Some w -> Ok w | None -> compile m)) members in
  List.iter (fun (n, w) -> match w with
      | Error e -> add "error" "wire" "%s: no wire: %s" n e | Ok _ -> ()) wires;
  let wire_of n = match List.assoc n wires with Ok (l, k) -> (l, k) | Error _ -> ([], "-") in
  let ports_of n = List.filter_map (fun l -> match String.split_on_char ' ' l with
      | ["B"; k; p] -> Some (k, p) | _ -> None) (fst (wire_of n)) in
  (* L23 levels: the weight port declared, the level pred level-first over type level, no belief in a count *)
  List.iter (fun m ->
      let models = List.filter_map (fun (_, spec) -> match spec with
          | M kv -> Option.map (fun v -> Filename.concat (Filename.dirname m.m_program) (str v)) (List.assoc_opt "model" kv)
          | _ -> None) (yfield m "evaluate") in
      let model_ports = List.concat_map (fun f ->
          try List.filter_map (fun l -> match String.split_on_char ' ' l with
              | ["B"; k; p] -> Some (k, p) | _ -> None) (fst (wire f))
          with _ -> []) models in
      let weight p = List.mem ("weight", p) (ports_of m.m_name @ model_ports) in
      List.iter (fun (b, spec) ->
          (match spec with
           | M kv -> (match List.assoc_opt "port" kv with
               | Some v when not (weight (str v)) ->
                 add "error" "L23" "link-levels: %s: belief %s's port %s is no weight port of its wire" m.m_name b (str v)
               | _ -> ())
           | _ -> ());
          if List.mem_assoc b m.m_init then
            add "error" "L23" "link-levels: %s: the belief pred %s has an #init count" m.m_name b) (yfield m "beliefs");
      List.iter (fun (lv, spec) ->
          let names = match spec with
            | M kv -> (match List.assoc_opt "names" kv with Some v -> strs v | None -> []) | _ -> [] in
          (match List.assoc_opt lv m.m_sigs with
           | Some (t :: _) when (match List.assoc_opt t m.m_types with
               | Some cs -> names = [] || uniq cs = uniq names | None -> false) -> ()
           | _ -> add "error" "L23" "link-levels: %s: the level pred %s's first argument is not a type of its names {%s}"
                    m.m_name lv (String.concat " " names));
          match spec with
          | M kv -> (match List.assoc_opt "from" kv with
              | Some (M [("belief", v)]) when not (weight (str v)) ->
                add "error" "L23" "link-levels: %s: level %s reads the port %s, no weight port of its wire" m.m_name lv (str v)
              | _ -> ())
          | _ -> ()) (yfield m "levels")) members;
  (* L19 bundles: a given sidecar's key is the wire's *)
  let bundle_file m f = Option.map (fun b -> Filename.concat (Filename.concat b m) f) o.bundles in
  List.iter (fun m ->
      match bundle_file m.m_name "sidecar.json" with
      | Some f when Sys.file_exists f ->
        let s = Image.read_file f and (_, k) = wire_of m.m_name in
        let needle = "\"key\": \"" ^ k ^ "\"" and needle2 = "\"key\":\"" ^ k ^ "\"" in
        let has sub = let n = String.length sub and l = String.length s in
          let rec go i = i + n <= l && (String.sub s i n = sub || go (i + 1)) in go 0 in
        if not (has needle || has needle2) then add "error" "L19" "link-key: %s's sidecar key is not its wire's %s" m.m_name k
      | Some _ -> add "error" "L19" "link-key: %s: no sidecar.json in --bundles" m.m_name
      | None -> ()) members;
  (* L25 planner *)
  (match d.planner_err with Some e -> add "error" "L25" "link-planner: %s" e | None -> ());
  (* the image *)
  let natures = match List.find_opt (fun i -> Some i.i_path = Option.map norm proto_path) a.a_ipkgs with
    | Some { i_nature = Some n; _ } -> n | _ -> [] in
  let shared_j m = Image.JO (List.map (fun (p, d) -> (p, Image.JS d)) m.m_shared) in
  let status_j m = Image.JO (List.map (fun (k, l) -> (k, Image.JL (List.map (fun x -> Image.JS x) l))) m.m_status) in
  let rec y_j = function
    | S s -> Image.JS s | L l -> Image.JL (List.map y_j l) | M kv -> Image.JO (List.map (fun (k, v) -> (k, y_j v)) kv) in
  let bundle_files m =
    let (wl, _) = wire_of m.m_name in
    [("ground.wire", String.concat "\n" wl ^ "\n")]
    @ (match bundle_file m.m_name "sidecar.json" with
        | Some f when Sys.file_exists f -> [("sidecar.json", Image.read_file f)] | _ -> []) in
  let bkey m = String.sub (Image.hash (bundle_files m)) 0 12 in
  let member_j m =
    let gen = m.m_role = "direct" && not hand in
    Image.JO ([("name", Image.JS m.m_name); ("role", Image.JS m.m_role);
               ("bundle", Image.JS ("members/" ^ m.m_name)); ("bundle_key", Image.JS (bkey m));
               ("wire_key", Image.JS (snd (wire_of m.m_name))); ("source_key", Image.JS m.m_key);
               ("program", Image.JS (Filename.basename m.m_program))]
              @ (if m.m_role = "direct" then [("generated", Image.JB gen)] else [])
              @ [("host", match host_of m with
                   | Some _ when host_missing m -> Image.JN     (* the loader refuses the member: load-host-missing *)
                   | Some (b, origin) -> Image.JO (List.map (fun (k, v) -> (k, Image.JS v)) b @ [("origin", Image.JS origin)])
                   | None -> Image.JN);
                 ("clock", match List.assoc_opt "clock" m.m_extra with Some v -> y_j v | None -> Image.JO [("beats", Image.JS "1")]);
                 ("response_turns", match rho with
                   | None -> Image.JN
                   | Some r ->
                     let period = match List.assoc_opt "clock" m.m_extra with
                       | Some (M kv) -> (match List.assoc_opt "period" kv with
                           | Some (S p) when p <> "" && p <> "null" -> int_of_string p | _ -> 1)
                       | _ -> 1 in
                     Image.JI (r * period));
                 ("shared", shared_j m); ("status", status_j m)]
              @ List.filter_map (fun k -> Option.map (fun v -> (k, y_j v)) (List.assoc_opt k m.m_extra))
                ["gating"; "resources"; "levels"; "beliefs"; "evaluate"; "display"; "line"; "voice"]) in
  let preds = uniq (List.concat_map (fun m -> List.map fst m.m_shared) members @ a.a_world_out @ a.a_world_in) in
  let who d p = List.filter_map (fun m -> if List.assoc_opt p m.m_shared = Some d then Some (Image.JS m.m_name) else None) members in
  let port_j p =
    let nature = match List.assoc_opt p natures with Some n -> n | None -> "state" in
    Image.JO [("pred", Image.JS p); ("nature", Image.JS nature);
              ("producers", Image.JL (who "out" p @ (if List.mem p a.a_world_out then [Image.JS "world"] else [])));
              ("consumers", Image.JL (who "in" p @ (if List.mem p a.a_world_in then [Image.JS "world"] else [])));
              ("holders", Image.JL (who "resource" p)); ("private", Image.JL (who "world-private" p))] in
  let image = Image.JO [
      ("format", Image.JS "metis-image/1"); ("name", Image.JS name);
      ("composition_key", Image.JS a.a_package_key);
      ("toolchain", Image.JO [("metisc", Image.JS "metisc"); ("spec", Image.JL [Image.JI 15; Image.JI 16; Image.JI 17])]);
      ("capacity", Image.JO [("domain", Image.JL (List.map (fun s -> Image.JS s) specialists));
                             ("resource", Image.JL (List.map (fun (r, _) -> Image.JS r) d.resources));
                             ("key", Image.JS a.a_cap_key)]);
      ("protocol", Image.JO [("file", Image.JS (match List.assoc_opt "protocol" comp with Some v -> str v | None -> ""));
                             ("key", Image.JS (match List.find_opt (fun i -> Some i.i_path = Option.map norm proto_path) a.a_ipkgs with
                                  | Some i -> i.i_key | None -> ""));
                             ("tokens", Image.JO (List.map (fun (p, n) -> (p, Image.JS n)) natures
                                                  @ List.map (fun t -> (t, Image.JS "injected")) ["tick"; "tick_s"; "changed"]))]);
      ("planner", match d.planner with Some p -> Image.JS p | None -> Image.JN);
      ("director", Image.JO [("name", Image.JS direct); ("generated", Image.JB (not hand));
                             ("facts", Image.JL (List.map (fun f -> Image.JS f) (director_facts d)));
                             ("kinds", Image.JL (List.map (fun k -> Image.JS k) d.kinds))]);
      ("members", Image.JL (List.map member_j (dm :: specs)));
      ("ports", Image.JL (List.map port_j preds));
      ("world", Image.JO [("out", Image.JL (List.map (fun p -> Image.JS p) a.a_world_out));
                          ("in", Image.JL (List.map (fun p -> Image.JS p) a.a_world_in))]);
      ("response", match rho with Some r -> Image.JI r | None -> Image.JN);
      ("priority", Image.JL (List.map (fun (p, q) -> Image.JL [Image.JS p; Image.JS q]) closed))] in
  let image_s = Image.to_string image in
  let tools = List.find_map (fun m -> match bundle_file m.m_name "tools.json" with
      | Some f when Sys.file_exists f -> Some (Image.read_file f) | _ -> None) (dm :: specs) in
  let files = [("image.json", image_s)]
              @ List.concat_map (fun m -> List.map (fun (f, c) -> ("members/" ^ m.m_name ^ "/" ^ f, c)) (bundle_files m)) (dm :: specs)
              @ (if hand then [] else [("members/" ^ direct ^ "/" ^ direct ^ ".llp", gen_llp);
                                       ]
                                       @ (if types = None then [("members/" ^ direct ^ "/capacity.llp", cap_text)] else [])
                                       @ [
                                       ("members/" ^ direct ^ "/domain.yaml", gen_man)])
              @ (match tools with Some t -> [("tools.json", t)] | None -> []) in
  let h = Image.hash files in
  let h12 = String.sub h 0 12 in
  (* the listing *)
  line "link %s" (Filename.basename comp_path);
  List.iter (fun m -> line "member %s %s wire %s bundle %s source %s" m.m_name m.m_role
                (snd (wire_of m.m_name)) (bkey m) m.m_key) (dm :: specs);
  line "director %s %s planner %s kinds %s" direct (if hand then "hand (transitional)" else "generated")
    (Option.value d.planner ~default:"-") (String.concat " " d.kinds);
  List.iter (fun f -> line "  %s" f) (director_facts d);
  let errs = List.filter (fun f -> f.sev = "error") (a.a_findings @ List.rev !fs) in
  let order s = match s with "error" -> 0 | "warning" -> 1 | _ -> 2 in
  let mine = List.stable_sort (fun x y -> compare (order x.sev) (order y.sev)) (List.rev !fs) in
  List.iter (fun f -> line "%s %s %s" f.sev f.chk f.text) mine;
  line "interface %d error(s), %d warning(s)" a.a_errors
    (List.length (List.filter (fun f -> f.sev = "warning") a.a_findings));
  List.iter (fun f -> if f.sev = "error" then line "error %s %s" f.chk f.text) a.a_findings;
  let n_err = List.length errs in
  if n_err = 0 then begin
    line "image %s v-%s" name h12;
    if not o.check then begin
      let dir = Filename.concat build (Printf.sprintf "%s.image.v-%s" name h12) in
      List.iter (fun (p, c) ->
          let f = Filename.concat dir p in
          Image.mkdir_p (Filename.dirname f); Image.write_file f c) files;
      (* a generated director's includes: the copies inside the image, never the link's temporary stage *)
      let inside f = let st = stage ^ "/" in
        if String.length f > String.length st && String.sub f 0 (String.length st) = st
        then "members/" ^ String.sub f (String.length st) (String.length f - String.length st) else f in
      let lock = Image.JO [
          ("members", Image.JO (List.map (fun m ->
               (m.m_name, Image.JO [("bundle", Image.JS (bkey m)); ("source", Image.JS m.m_key);
                                    ("program", Image.JS (snd (wire_of m.m_name)));
                                    ("includes", Image.JL (List.map (fun (s, place, f) ->
                                         Image.JO [("name", Image.JS s); ("place", Image.JS place); ("path", Image.JS (inside f))]) m.m_inc))]))
               (dm :: specs)));
          ("iface", Image.JO (List.map (fun i -> (Filename.basename i.i_path, Image.JS i.i_key)) a.a_ipkgs));
          ("capacity", Image.JO [("file", Image.JS (Filename.basename capacity)); ("key", Image.JS a.a_cap_key)]);
          ("places", Image.JO [("root", Image.JS comp_dir);
                               ("home", match Sys.getenv_opt "METIS_HOME" with Some h -> Image.JS h | None -> Image.JN)]);
          ("image", Image.JS h)] in
      let lock_s = Image.to_string lock in
      Image.write_file (Filename.concat dir "image.lock") lock_s;
      if o.tar then Image.write_file (dir ^ ".tar")      (* the lock rides along, outside the hash *)
          (Image.tar (List.map (fun (p, c) -> (Printf.sprintf "%s.image.v-%s/%s" name h12 p, c))
                        (files @ [("image.lock", lock_s)])));
      line "wrote %s.image.v-%s%s" name h12 (if o.tar then " (+ .tar)" else "");
      if o.build then begin
        Image.write_file record (String.concat "\n"
          ((Printf.sprintf "image %s.image.v-%s" name h12)
           :: List.map (fun m -> Printf.sprintf "member %s %s %s" m.m_name (build_key m) (snd (wire_of m.m_name))) (dm :: specs)) ^ "\n");
        let names = List.map (fun m -> m.m_name) (dm :: specs) in
        let r = List.filter (fun n -> List.mem n !reused) names and c = List.filter (fun n -> not (List.mem n !reused)) names in
        line "build reused %d [%s] compiled %d [%s]" (List.length r) (String.concat " " r) (List.length c) (String.concat " " c)
      end
    end
  end;
  List.iter (fun f -> let f = Filename.concat stage_dir f in if Sys.file_exists f then Sys.remove f)
    [direct ^ ".llp"; "domain.yaml"; "capacity.llp"];
  (try Sys.rmdir stage_dir; Sys.rmdir stage with Sys_error _ -> ());
  line "result %d error(s), %d warning(s)" n_err
    (List.length (List.filter (fun f -> f.sev = "warning") (a.a_findings @ !fs)));
  (List.rev !lines, n_err)
