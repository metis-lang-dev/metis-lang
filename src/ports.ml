(* SPDX-License-Identifier: Apache-2.0 *)
open Ast

type hook = {
  hk_factor : string;
  hk_args : string list;
  hk_scope : string list;
  hk_compl : bool }

let dedup xs =
  List.rev (List.fold_left (fun acc x ->
      if List.mem x acc then acc else x :: acc) [] xs)

let render pred terms =
  if terms = [] then pred
  else Printf.sprintf "%s(%s)" pred (String.concat "," terms)

let ground_reads (ports : Compile.ports) factor args horn =
  let pats = match List.assoc_opt factor ports.p_reads with
    | Some p -> p
    | None -> raise (Compile.Lang_error
                       [Printf.sprintf
                          "weight port '%s' declares no read scope"
                          factor]) in
  let formals = List.assoc factor ports.p_weights in
  let subst = List.combine formals args in
  let resolve = function
    | TConst v -> v
    | TVar v ->
      (match List.assoc_opt v subst with
       | Some c -> c | None -> "?" ^ v) in
  let out = List.concat_map (fun (pat : read_pattern) ->
      let head = List.map resolve pat.ratom.terms in
      if pat.rguards = [] then [render pat.ratom.pred head]
      else
        let goals = List.map (fun (g : atom) ->
            (g.pred, List.map resolve g.terms)) pat.rguards in
        List.map (fun sol ->
            render pat.ratom.pred
              (List.map (fun a ->
                   if String.length a > 0 && a.[0] = '?' then
                     let v = String.sub a 1 (String.length a - 1) in
                     (match List.assoc_opt v sol with
                      | Some c -> c | None -> a)
                   else a)
                  head))
          (Horn.solutions horn goals))
      pats in
  dedup out

let horn_db (cat : Catalog.t) =
  Horn.make
    (List.filter_map (fun (e : Catalog.entry) ->
         match e.e_payload with
         | Catalog.PHorn h ->
           Some { Horn.head = h.h_head; body = h.h_body;
                  vars = h.h_vars }
         | _ -> None)
       cat.k_entries)

let base_name ev_name =
  match String.index_opt ev_name '[' with
  | Some i -> String.sub ev_name 0 i
  | None -> ev_name

let tag_subst ev_name =
  match String.index_opt ev_name '[' with
  | None -> []
  | Some i ->
    let inner = String.sub ev_name (i + 1)
        (String.length ev_name - i - 2) in
    if inner = "" then []
    else List.map (fun kv ->
        match String.index_opt kv '=' with
        | Some j -> (String.sub kv 0 j,
                     String.sub kv (j + 1)
                       (String.length kv - j - 1))
        | None -> (kv, kv))
        (String.split_on_char ',' inner)

let hooks prog (ports : Compile.ports) cat =
  let opaque = List.filter_map (fun (_, r) ->
      if List.mem_assoc r.Compile.w_factor ports.p_reads then None
      else Some r.Compile.w_factor)
      ports.p_weight_refs in
  (match List.sort_uniq compare opaque with
   | [] -> ()
   | ms -> raise (Compile.Lang_error
                    (List.map (fun m ->
                         Printf.sprintf
                           "weight port '%s' declares no read scope \
                            — required for factoring" m) ms)));
  let horn = horn_db cat in
  List.filter_map (fun (ev : Ground.event) ->
      if ev.ev_pre <> None then None
      else
        let base = base_name ev.ev_name in
        match List.assoc_opt base ports.p_weight_refs with
        | None -> None
        | Some r ->
          let subst = tag_subst ev.ev_name in
          let args = List.map (fun a ->
              match List.assoc_opt a subst with
              | Some c -> c | None -> a)
              r.Compile.w_args in
          Some (ev.ev_name,
                { hk_factor = r.Compile.w_factor; hk_args = args;
                  hk_scope = ground_reads ports r.Compile.w_factor
                      args horn;
                  hk_compl = r.Compile.w_compl }))
    (Ground.events prog)
