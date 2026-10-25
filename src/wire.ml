(* SPDX-License-Identifier: Apache-2.0 *)

(* python-dict merge {**a, **b}: a's keys in place (b's value wins),
   b's new keys appended *)
let dict_merge a b =
  List.map (fun (k, v) ->
      match List.assoc_opt k b with Some v' -> (k, v') | None -> (k, v)) a
  @ List.filter (fun (k, _) -> not (List.mem_assoc k a)) b

let merge_ports (a : Compile.ports) (b : Compile.ports) : Compile.ports =
  let append xs ys = xs @ List.filter (fun y -> not (List.mem y xs)) ys in
  { Compile.p_weights = dict_merge a.p_weights b.p_weights;
    p_reads = dict_merge a.p_reads b.p_reads;
    p_weight_refs = dict_merge a.p_weight_refs b.p_weight_refs;
    p_guards = dict_merge a.p_guards b.p_guards;
    p_inputs = append a.p_inputs b.p_inputs;
    p_outputs = append a.p_outputs b.p_outputs }

(* python repr(float): the shortest digits that round-trip, positional
   for a decimal exponent in [-4, 16), else d.ddde±XX *)
let repr_float w =
  if Float.is_nan w then "nan"
  else if Float.abs w = Float.infinity then
    (if w > 0. then "inf" else "-inf")
  else begin
    let rec shortest p =
      let s = Printf.sprintf "%.*e" (p - 1) w in
      if p >= 17 || float_of_string s = w then s else shortest (p + 1) in
    let s = shortest 1 in
    let neg = s.[0] = '-' in
    let s = if neg then String.sub s 1 (String.length s - 1) else s in
    let epos = String.index s 'e' in
    let mant = String.sub s 0 epos in
    let x = int_of_string (String.sub s (epos + 1)
                             (String.length s - epos - 1)) in
    let digits = String.concat "" (String.split_on_char '.' mant) in
    (* the shortest form has no trailing zeros but its first digit *)
    let digits =
      let n = ref (String.length digits) in
      while !n > 1 && digits.[!n - 1] = '0' do decr n done;
      String.sub digits 0 !n in
    let nd = String.length digits in
    let body =
      if x >= -4 && x < 16 then
        if x >= 0 then
          if nd <= x + 1 then digits ^ String.make (x + 1 - nd) '0' ^ ".0"
          else String.sub digits 0 (x + 1) ^ "."
               ^ String.sub digits (x + 1) (nd - x - 1)
        else "0." ^ String.make (- x - 1) '0' ^ digits
      else
        let m = if nd = 1 then digits
          else String.sub digits 0 1 ^ "." ^ String.sub digits 1 (nd - 1) in
        Printf.sprintf "%se%c%02d" m (if x < 0 then '-' else '+') (abs x) in
    (if neg then "-" else "") ^ body
  end

let weight_text w =
  if w = 0. then "0"
  else if Float.is_integer w && Float.abs w < 9007199254740992. then
    Printf.sprintf "%.0f" w
  else repr_float w

let base_name n =
  match String.index_opt n '[' with Some i -> String.sub n 0 i | None -> n

(* the event tag's substitution: schema[X=c,Y=d] -> [X,c; Y,d] *)
let tag_subst n =
  match String.index_opt n '[' with
  | None -> []
  | Some i ->
    let inner = String.sub n (i + 1) (String.length n - i - 2) in
    if inner = "" then []
    else List.map (fun kv ->
        match String.index_opt kv '=' with
        | Some j -> (String.sub kv 0 j,
                     String.sub kv (j + 1) (String.length kv - j - 1))
        | None -> failwith ("bad event tag: " ^ n))
        (String.split_on_char ',' inner)

let sections (ev : Ground.event) =
  let b = Buffer.create 64 in
  List.iter (fun (tag, d) ->
      if d <> [] then begin
        Buffer.add_string b (" ; " ^ tag);
        List.iter (fun (a, n) -> Printf.bprintf b " %s %d" a n)
          (List.sort compare d)
      end)
    [("c", ev.ev_consume); ("o", ev.ev_produce); ("p", ev.ev_persist)];
  Buffer.contents b

let wsection (ports : Compile.ports) (ev : Ground.event) =
  match List.assoc_opt (base_name ev.ev_name) ports.p_weight_refs with
  | None -> ""
  | Some r ->
    let subst = tag_subst ev.ev_name in
    Printf.sprintf " ; w %s %d%s" r.Compile.w_factor
      (if r.Compile.w_compl then 1 else 0)
      (String.concat "" (List.map (fun a ->
           " " ^ (match List.assoc_opt a subst with
               | Some c -> c | None -> a)) r.Compile.w_args))

let artifact_lines (cat : Catalog.t) (ports : Compile.ports)
    (prog : Ground.program) steps =
  let names = List.map fst prog.stages in
  let idx s =
    let rec go i = function
      | [] -> failwith ("unknown stage: " ^ s)
      | x :: r -> if x = s then i else go (i + 1) r in
    go 0 names in
  let header = Printf.sprintf
      "# metis ground-wire artifact \xe2\x80\x94 catalog %s v%d; \
       GENERATED, do not edit." cat.k_name cat.k_version in
  let manifest =
    List.map (fun n -> "B in " ^ n) (List.sort compare ports.p_inputs)
    @ List.map (fun n -> "B out " ^ n) (List.sort compare ports.p_outputs)
    @ List.map (fun n -> "B guard " ^ n)
      (List.sort compare (List.map fst ports.p_guards))
    @ List.map (fun n -> "B weight " ^ n)
      (List.sort compare (List.map fst ports.p_weights)) in
  let event stage post (ev : Ground.event) =
    Printf.sprintf "E %d %d %s %s%s%s" stage post (weight_text ev.ev_weight)
      (String.map (fun c -> if c = ' ' then '_' else c) ev.ev_name)
      (sections ev) (wsection ports ev) in
  (* tail-recursive map and append: the stdlib's List.map and (@) are
     not, and overflow the 8 MB stack at ~1M events (eval-perf step 2f) *)
  let map f l = List.rev (List.rev_map f l) in
  let ( @ ) a b = List.rev_append (List.rev a) b in
  let clauses = List.concat_map (fun (s, evs) ->
      map (event (idx s) (-1)) evs) prog.stages in
  let links = map (fun (ev : Ground.event) ->
      match ev.ev_pre, ev.ev_post with
      | Some pre, Some post -> event (idx pre) (idx post) ev
      | _ -> failwith ("link without pre/post: " ^ ev.ev_name))
      prog.links in
  let init = String.concat " "
      (List.map (fun (a, n) -> Printf.sprintf "%s %d" a n)
         (List.sort compare prog.init)) in
  [header; Printf.sprintf "N %d %d" (List.length names)
     (idx prog.init_stage)]
  @ manifest @ clauses @ links
  @ ["I " ^ init; Printf.sprintf "S %d" steps]
