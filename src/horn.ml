type pattern = string * string list

type clause = { head : pattern; body : pattern list;
                vars : string list }

type db = { by_pred : (string, clause list) Hashtbl.t;
            mutable fresh : int }

let depth_bound = 256

let make clauses =
  let by_pred = Hashtbl.create 16 in
  List.iter (fun c ->
      let k = fst c.head in
      let cur = try Hashtbl.find by_pred k with Not_found -> [] in
      Hashtbl.replace by_pred k (cur @ [c]))
    clauses;
  { by_pred; fresh = 0 }

let is_qvar t = String.length t > 0 && t.[0] = '?'

let rename db cl =
  if cl.vars = [] then cl
  else begin
    db.fresh <- db.fresh + 1;
    let m = List.map (fun v ->
        (v, Printf.sprintf "?%s@%d" v db.fresh)) cl.vars in
    let r (p, args) =
      (p, List.map (fun a ->
           match List.assoc_opt a m with Some x -> x | None -> a)
          args) in
    { head = r cl.head; body = List.map r cl.body; vars = [] }
  end

let rec walk t subst =
  if is_qvar t then
    match List.assoc_opt t subst with
    | Some t' -> walk t' subst
    | None -> t
  else t

let unify (pa, aa) (pb, ab) subst =
  if pa <> pb || List.length aa <> List.length ab then None
  else
    let rec go s = function
      | [], [] -> Some s
      | x :: xs, y :: ys ->
        let x = walk x s and y = walk y s in
        if x = y then go s (xs, ys)
        else if is_qvar x then go ((x, y) :: s) (xs, ys)
        else if is_qvar y then go ((y, x) :: s) (xs, ys)
        else None
      | _ -> None in
    go subst (aa, ab)

(* depth-first SLD; calls k on every solution substitution, in
   enumeration order; k returns true to STOP (early exit) *)
let rec solve db goals subst depth k =
  match goals with
  | [] -> k subst
  | g0 :: rest ->
    if depth <= 0 then false
    else begin
      let g = (fst g0, List.map (fun a -> walk a subst) (snd g0)) in
      let cls =
        try Hashtbl.find db.by_pred (fst g) with Not_found -> [] in
      List.exists (fun cl ->
          let r = rename db cl in
          match unify r.head g subst with
          | None -> false
          | Some s2 -> solve db (r.body @ rest) s2 (depth - 1) k)
        cls
    end

let derivable db goal =
  solve db [goal] [] depth_bound (fun _ -> true)

let solutions db goals =
  let vs = List.sort_uniq compare
      (List.concat_map (fun (_, args) -> List.filter is_qvar args)
         goals) in
  let seen = Hashtbl.create 16 in
  let out = ref [] in
  ignore (solve db goals [] depth_bound (fun s ->
      let key = List.map (fun v -> walk v s) vs in
      if List.exists is_qvar key then
        (* a quantified fact var answered the query without being
           pinned: enumerable only through its type, which the Horn
           world does not carry *)
        failwith "non-ground Horn solution: a fact variable is left \
                  unbound — guard it with a predicate that enumerates it";
      if not (Hashtbl.mem seen key) then begin
        Hashtbl.add seen key ();
        out := List.map2 (fun v c ->
            (String.sub v 1 (String.length v - 1), c)) vs key
               :: !out
      end;
      false));
  List.rev !out
