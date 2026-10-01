open Ast
open Lexer

exception Parse_error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Parse_error s)) fmt

type st = { toks : token array; poss : (int * int) array;
            mutable i : int; mutable docs : string list }

let mk (toks, poss) =
  { toks = Array.of_list toks; poss; i = 0; docs = [] }

(* line:col of token index k (default: the token just consumed) *)
let where ?k p =
  let j = match k with Some k -> k | None -> p.i - 1 in
  if Array.length p.poss = 0 then "1:1"
  else
    let j = max 0 (min j (Array.length p.poss - 1)) in
    let (l, c) = p.poss.(j) in
    Printf.sprintf "%d:%d" l c

let peek ?(k = 0) p =
  if p.i + k < Array.length p.toks then Some p.toks.(p.i + k) else None

let next p =
  let t = peek p in p.i <- p.i + 1;
  match t with Some t -> t | None -> fail "unexpected end of input"

let expect_ident p = match next p with
  | Ident v -> v | _ -> fail "%s: expected identifier" (where p)

let expect_num p = match next p with
  | Num v -> v | _ -> fail "%s: expected number" (where p)

let expect_str p = match next p with
  | Str v -> v | _ -> fail "%s: expected string" (where p)

let punct p ch = match next p with
  | Punct c when c = ch -> ()
  | _ -> fail "%s: expected '%c'" (where p) ch

let expect_kw p kw =
  let v = expect_ident p in
  if v <> kw then fail "expected %s, got %s" kw v

let take_docs p =
  let d = String.concat "\n" (List.rev p.docs) in p.docs <- []; d

let drain_docs p =
  let rec go () = match peek p with
    | Some (Doc d) -> p.i <- p.i + 1; p.docs <- d :: p.docs; go ()
    | _ -> () in
  go ()

(* range sugar: shared alpha prefix, inclusive int suffixes *)
let split_range_end s =
  let n = String.length s in
  let j = ref n in
  while !j > 0 && s.[!j - 1] >= '0' && s.[!j - 1] <= '9' do decr j done;
  if !j = n then None
  else Some (String.sub s 0 !j, int_of_string (String.sub s !j (n - !j)))

let expand_range a b =
  match split_range_end a, split_range_end b with
  | Some (pa, ia), Some (pb, ib) when pa = pb && ia <= ib ->
    List.init (ib - ia + 1) (fun k -> Printf.sprintf "%s%d" pa (ia + k))
  | _ -> fail "bad range %s..%s" a b

(* -- terms / atoms ---------------------------------------------------- *)

let is_upper s = s <> "" && s.[0] >= 'A' && s.[0] <= 'Z'

let term p = match next p with
  | Num v -> TConst v
  | Ident v -> if is_upper v then TVar v else TConst v
  | _ -> fail "%s: expected term" (where p)

let atom p =
  let persist = (peek p = Some (Punct '$')) in
  if persist then ignore (next p);
  let name = expect_ident p in
  let terms =
    if peek p <> Some (Punct '(') then []
    else begin
      ignore (next p);
      let rec go acc =
        let t = term p in
        match next p with
        | Punct ')' -> List.rev (t :: acc)
        | Punct ',' -> go (t :: acc)
        | _ -> fail "%s: expected , or )" (where p) in
      go []
    end in
  { pred = name; terms; persist }

let body_elem p =
  match peek p, peek ~k:1 p with
  | Some (Ident v), Some Ne when is_upper v ->
    ignore (next p); ignore (next p);
    BDistinct (v, expect_ident p)
  | _ -> BAtom (atom p)

let star_list p elem =
  let rec go acc =
    if peek p = Some (Punct '*') then begin
      ignore (next p); go (elem p :: acc)
    end else List.rev acc in
  go [elem p]

(* -- declarations ----------------------------------------------------- *)

let name_list_paren p =
  punct p '(';
  let rec go acc = match peek p with
    | Some (Punct ')') -> ignore (next p); List.rev acc
    | _ -> go (expect_ident p :: acc) in
  go []

let sig_args p =
  if peek p <> Some (Punct '(') then []
  else begin
    ignore (next p);
    let rec go acc =
      let v = expect_ident p in
      match next p with
      | Punct ')' -> List.rev (v :: acc)
      | Punct ',' -> go (v :: acc)
      | _ -> fail "%s: expected , or )" (where p) in
    go []
  end

let weight_expr p = match peek p with
  | Some (Num v) -> ignore (next p); WVal (float_of_string v)
  | _ ->
    let complement = (peek p = Some (Punct '~')) in
    if complement then ignore (next p);
    let factor = expect_ident p in
    let wargs =
      if peek p <> Some (Punct '(') then []
      else begin
        ignore (next p);
        let rec go acc = match peek p with
          | Some (Punct ')') -> ignore (next p); List.rev acc
          | _ ->
            let t = term p in
            if peek p = Some (Punct ',') then ignore (next p);
            go (t :: acc) in
        go []
      end in
    WRef { factor; wargs; complement }

let read_pattern p =
  let a = atom p in
  let rguards =
    if peek p = Some (Ident "if") then begin
      ignore (next p); star_list p atom
    end else [] in
  { ratom = a; rguards }

let reads_block p =
  punct p '{';
  let rec go acc = match peek p with
    | Some (Punct '}') -> ignore (next p); List.rev acc
    | _ ->
      let r = read_pattern p in
      if peek p = Some (Punct ',') then ignore (next p);
      go (r :: acc) in
  go []

let unit_atom = { pred = "one"; terms = []; persist = false }

(* a head position: '()' is the LL unit (alias of 'one'), else a
   '*'-list of atoms *)
let head_atoms p =
  if peek p = Some (Punct '(') && peek ~k:1 p = Some (Punct ')') then
    begin ignore (next p); ignore (next p); [unit_atom] end
  else star_list p atom

(* a rule parses to ONE OR MORE clauses: the alternative-head sugar
   '-o ( head @w w | head @w w ... )' expands here, in the parser,
   exactly as type-range sugar does — the AST, the compiled catalog
   and the canonical key see only the expanded clauses, named
   <name>-1 .. <name>-k. Sharing the body, the branches share the
   anchor token and form one CHOICE site: the weighted internal
   choice (the additive ⊕), with no kernel change. *)
let rule p =
  let rdoc = take_docs p in
  let rname = expect_ident p in
  punct p '['; let rlayer = expect_ident p in punct p ']';
  punct p ':';
  let rbody = star_list p body_elem in
  (match next p with Arrow -> () | _ -> fail "%s: expected -o" (where p));
  if peek p = Some (Punct '(')
     && peek ~k:1 p <> Some (Punct ')') then begin
    ignore (next p);
    let branch () =
      let h = head_atoms p in
      (match peek p with
       | Some AtW -> ignore (next p)
       | _ -> fail "alternative head: every branch needs '@w' \
                    (rule %s)" rname);
      (h, weight_expr p) in
    let rec go acc =
      let b = branch () in
      match next p with
      | Punct '|' -> go (b :: acc)
      | Punct ')' -> List.rev (b :: acc)
      | _ -> fail "%s: expected '|' or ')' in alternative head \
                   (rule %s)" (where p) rname in
    let branches = go [] in
    if List.length branches < 2 then
      fail "alternative head needs >= 2 branches (rule %s)" rname;
    punct p '.';
    List.mapi (fun k (rhead, w) ->
        { rname = Printf.sprintf "%s-%d" rname (k + 1);
          rlayer; rdoc; rbody; rhead; rweight = Some w })
      branches
  end else begin
    let rhead = head_atoms p in
    let rweight =
      if peek p = Some AtW then begin
        ignore (next p); Some (weight_expr p)
      end else None in
    punct p '.';
    [{ rname; rlayer; rdoc; rbody; rhead; rweight }]
  end

let stage_def p =
  let sname = expect_ident p in
  punct p '{';
  let rec go acc =
    drain_docs p;
    if peek p = Some (Punct '}') then begin
      ignore (next p); List.concat (List.rev acc)
    end else go (rule p :: acc) in
  let srules = go [] in
  let seen = Hashtbl.create 16 in
  List.iter (fun r ->
      if Hashtbl.mem seen r.rname then
        fail "duplicate rule name %s in stage %s \
              (note: alternative heads reserve <name>-<k>)"
          r.rname sname;
      Hashtbl.add seen r.rname ()) srules;
  { sname; srules }

let link_def p =
  let ldoc = take_docs p in
  let lname = expect_ident p in
  punct p '['; let llayer = expect_ident p in punct p ']';
  punct p ':';
  let lpre = expect_ident p in
  let lpre_atoms =
    if peek p = Some (Punct '*') then begin
      ignore (next p); star_list p atom
    end else [] in
  (match next p with Arrow -> () | _ ->
     fail "%s: expected -o" (where p));
  let lpost = expect_ident p in
  let lpost_atoms =
    if peek p = Some (Punct '*') then begin
      ignore (next p); star_list p atom
    end else [] in
  punct p '.';
  { lname; llayer; ldoc; lpre; lpre_atoms; lpost; lpost_atoms }

let type_consts p =
  punct p '{';
  let const_tok () = match next p with
    | Ident v | Num v -> v
    | _ -> fail "%s: bad type constant" (where p) in
  let rec go acc = match peek p with
    | Some (Punct '}') -> ignore (next p); List.rev acc
    | _ ->
      let v = const_tok () in
      if peek p = Some Range then begin
        ignore (next p);
        let v2 = const_tok () in
        go (List.rev_append (expand_range v v2) acc)
      end else go (v :: acc) in
  go []

let parse text =
  let p = mk (Lexer.tokens_pos text) in
  drain_docs p;
  expect_kw p "catalog";
  let cname = expect_ident p in
  let cversion = int_of_string (expect_num p) in
  punct p '.';
  let cprov = ref None and cextends = ref None in
  let clayers = ref [] and cstages = ref [] in
  let decls = ref [] in
  let add d = decls := d :: !decls in
  let rec loop () =
    drain_docs p;
    match peek p with
    | None -> ()
    | Some (Ident v) ->
      (match v with
       | "include" -> ignore (next p);
         let path = expect_str p in punct p '.'; add (DInclude path)
       | "extends" -> ignore (next p);
         cextends := Some (expect_ident p); punct p '.'
       | "provenance" -> ignore (next p);
         let s = expect_ident p in
         let r = expect_str p in let d = expect_str p in
         punct p '.'; cprov := Some (s, r, d)
       | "layers" -> ignore (next p);
         clayers := name_list_paren p; punct p '.'
       | "stages" when peek ~k:1 p = Some (Punct '(') ->
         ignore (next p); cstages := name_list_paren p; punct p '.'
       | "type" -> ignore (next p);
         let tname = expect_ident p in
         let consts = type_consts p in
         punct p '.'; add (DType (tname, consts))
       | "namespace" -> ignore (next p);
         let nname = expect_ident p in
         expect_kw p "produce";
         let produce = name_list_paren p in
         let consume =
           if peek p = Some (Ident "consume") then begin
             ignore (next p); Some (name_list_paren p)
           end else None in
         punct p '.'; add (DNamespace (nname, produce, consume))
       | "pred" -> ignore (next p);
         let pname = expect_ident p in
         let args = sig_args p in
         punct p ':';
         let space = expect_ident p in
         punct p '.'; add (DPred (pname, args, space))
       | "bwd" -> ignore (next p);
         let bname = expect_ident p in
         let args = sig_args p in
         punct p '.'; add (DBwd (bname, args))
       | "weight" | "guard" | "input" | "output" -> ignore (next p);
         let pkind = match v with
           | "weight" -> Weight | "guard" -> Guard
           | "input" -> Input | _ -> Output in
         let pname = expect_ident p in
         let pargs = sig_args p in
         let preads =
           if peek p = Some (Ident "reads") then begin
             if pkind <> Weight then
               fail "%s port %s: reads is for weight ports only" v
                 pname;
             ignore (next p); Some (reads_block p)
           end else None in
         punct p '.'; add (DPort { pkind; pname; pargs; preads })
       | "stage" -> ignore (next p); add (DStage (stage_def p))
       | "qui" -> ignore (next p); add (DLink (link_def p))
       | _ ->
         (* bare atom: Horn fact or rule *)
         let head = atom p in
         if peek p = Some HornSep then begin
           ignore (next p);
           let rec go acc =
             let b = atom p in
             if peek p = Some (Punct ',') then begin
               ignore (next p); go (b :: acc)
             end else List.rev (b :: acc) in
           let body = go [] in
           punct p '.'; add (DHorn (head, body))
         end else begin punct p '.'; add (DFact head) end);
      loop ()
    | Some _ -> fail "%s: expected declaration" (where ~k:p.i p) in
  loop ();
  { cname; cversion; cprov = !cprov; clayers = !clayers;
    cstages = !cstages; cextends = !cextends;
    cdecls = List.rev !decls }

let parse_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; parse s
