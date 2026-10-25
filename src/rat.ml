(* SPDX-License-Identifier: Apache-2.0 *)

(* -- naturals: little-endian int arrays, base 2^24, no high zero limb -- *)

let bb = 24
let base = 1 lsl bb
let mask = base - 1

let norm a =
  let n = ref (Array.length a) in
  while !n > 0 && a.(!n - 1) = 0 do decr n done;
  if !n = Array.length a then a else Array.sub a 0 !n

let nzero = [||]

let nof_int x =
  let rec go x acc = if x = 0 then List.rev acc else go (x lsr bb) ((x land mask) :: acc) in
  Array.of_list (go x [])

let ncmp a b =
  let la = Array.length a and lb = Array.length b in
  if la <> lb then compare la lb
  else begin
    let r = ref 0 and i = ref (la - 1) in
    while !r = 0 && !i >= 0 do
      r := compare a.(!i) b.(!i); decr i
    done;
    !r
  end

let nadd a b =
  let a, b = if Array.length a >= Array.length b then a, b else b, a in
  let la = Array.length a and lb = Array.length b in
  let out = Array.make (la + 1) 0 in
  let carry = ref 0 in
  for i = 0 to la - 1 do
    let t = a.(i) + (if i < lb then b.(i) else 0) + !carry in
    out.(i) <- t land mask; carry := t lsr bb
  done;
  out.(la) <- !carry;
  norm out

(* a - b, a >= b *)
let nsub a b =
  let la = Array.length a and lb = Array.length b in
  let out = Array.make la 0 in
  let borrow = ref 0 in
  for i = 0 to la - 1 do
    let t = a.(i) - (if i < lb then b.(i) else 0) - !borrow in
    if t < 0 then (out.(i) <- t + base; borrow := 1)
    else (out.(i) <- t; borrow := 0)
  done;
  norm out

let nmul a b =
  let la = Array.length a and lb = Array.length b in
  if la = 0 || lb = 0 then nzero
  else begin
    let out = Array.make (la + lb) 0 in
    for i = 0 to la - 1 do
      let carry = ref 0 in
      let ai = a.(i) in
      for j = 0 to lb - 1 do
        let t = out.(i + j) + ai * b.(j) + !carry in
        out.(i + j) <- t land mask; carry := t lsr bb
      done;
      let k = ref (i + lb) in
      while !carry > 0 do
        let t = out.(!k) + !carry in
        out.(!k) <- t land mask; carry := t lsr bb; incr k
      done
    done;
    norm out
  end

(* a / d, a mod d for 0 < d < 2^24 *)
let ndivmod_small a d =
  let la = Array.length a in
  let q = Array.make la 0 in
  let r = ref 0 in
  for i = la - 1 downto 0 do
    let t = (!r lsl bb) lor a.(i) in
    q.(i) <- t / d; r := t mod d
  done;
  (norm q, !r)

(* a shifted left by s bits, 0 <= s < 24: one more limb, unnormalised *)
let shl_bits a s =
  let la = Array.length a in
  let out = Array.make (la + 1) 0 in
  let carry = ref 0 in
  for i = 0 to la - 1 do
    let t = (a.(i) lsl s) lor !carry in
    out.(i) <- t land mask; carry := t lsr bb
  done;
  out.(la) <- !carry;
  out

let shr_bits a s =
  if s = 0 then norm a
  else begin
    let la = Array.length a in
    let out = Array.make la 0 in
    for i = 0 to la - 1 do
      let hi = if i + 1 < la then (a.(i + 1) lsl (bb - s)) land mask else 0 in
      out.(i) <- (a.(i) lsr s) lor hi
    done;
    norm out
  end

(* Knuth's algorithm D *)
let ndivmod u v =
  if Array.length v = 0 then invalid_arg "Rat: division by zero";
  if ncmp u v < 0 then (nzero, u)
  else if Array.length v = 1 then
    let (q, r) = ndivmod_small u v.(0) in (q, nof_int r)
  else begin
    let n = Array.length v in
    let s = ref 0 in
    while (v.(n - 1) lsl !s) land (1 lsl (bb - 1)) = 0 do incr s done;
    let vn = Array.sub (shl_bits v !s) 0 n in
    let un = shl_bits u !s in                      (* length m + n + 1 *)
    let m = Array.length un - n - 1 in
    let q = Array.make (m + 1) 0 in
    for j = m downto 0 do
      let num = (un.(j + n) lsl bb) lor un.(j + n - 1) in
      let qhat = ref (num / vn.(n - 1)) and rhat = ref (num mod vn.(n - 1)) in
      let continue = ref true in
      while !continue
            && (!qhat >= base
                || !qhat * vn.(n - 2) > (!rhat lsl bb) lor un.(j + n - 2)) do
        decr qhat; rhat := !rhat + vn.(n - 1);
        if !rhat >= base then continue := false
      done;
      let borrow = ref 0 and carry = ref 0 in
      for i = 0 to n - 1 do
        let p = !qhat * vn.(i) + !carry in
        carry := p lsr bb;
        let t = un.(i + j) - (p land mask) - !borrow in
        if t < 0 then (un.(i + j) <- t + base; borrow := 1)
        else (un.(i + j) <- t; borrow := 0)
      done;
      let t = un.(j + n) - !carry - !borrow in
      if t < 0 then begin
        un.(j + n) <- t + base;
        decr qhat;
        let c = ref 0 in
        for i = 0 to n - 1 do
          let t = un.(i + j) + vn.(i) + !c in
          un.(i + j) <- t land mask; c := t lsr bb
        done;
        un.(j + n) <- (un.(j + n) + !c) land mask
      end else un.(j + n) <- t;
      q.(j) <- !qhat
    done;
    (norm q, shr_bits (Array.sub un 0 n) !s)
  end

let rec ngcd a b = if Array.length b = 0 then a else ngcd b (snd (ndivmod a b))

let nbits a =
  let la = Array.length a in
  if la = 0 then 0
  else begin
    let top = a.(la - 1) in
    let k = ref 0 in
    while top lsr !k > 0 do incr k done;
    (la - 1) * bb + !k
  end

let nto_string a =
  if Array.length a = 0 then "0"
  else begin
    let chunks = ref [] and x = ref a in
    while Array.length !x > 0 do
      let (q, r) = ndivmod_small !x 1_000_000 in
      chunks := r :: !chunks; x := q
    done;
    match !chunks with
    | [] -> "0"
    | h :: rest ->
      String.concat "" (string_of_int h :: List.map (Printf.sprintf "%06d") rest)
  end

let nof_digits s =
  let r = ref nzero in
  String.iter (fun c ->
      r := nadd (nmul !r (nof_int 10)) (nof_int (Char.code c - 48))) s;
  !r

let npow10 k =
  let r = ref (nof_int 1) in
  for _ = 1 to k do r := nmul !r (nof_int 10) done;
  !r

let nto_int a = Array.fold_right (fun l acc -> (acc lsl bb) lor l) a 0

let nshl a k =                                       (* a * 2^k *)
  let limbs = k / bb and s = k mod bb in
  let a = norm (shl_bits a s) in
  if Array.length a = 0 then a else Array.append (Array.make limbs 0) a

(* -- rationals: reduced, denominator > 0 ------------------------------ *)

type t = { n : int array; d : int array }

exception Negative of string

let make n d =
  if Array.length n = 0 then { n = nzero; d = nof_int 1 }
  else
    let g = ngcd n d in
    if ncmp g (nof_int 1) = 0 then { n; d }
    else { n = fst (ndivmod n g); d = fst (ndivmod d g) }

let zero = { n = nzero; d = nof_int 1 }
let one = { n = nof_int 1; d = nof_int 1 }
let of_int x = if x < 0 then raise (Negative "of_int") else make (nof_int x) (nof_int 1)
let is_zero a = Array.length a.n = 0

let add a b =
  if is_zero a then b else if is_zero b then a
  else if ncmp a.d b.d = 0 then make (nadd a.n b.n) a.d
  else make (nadd (nmul a.n b.d) (nmul b.n a.d)) (nmul a.d b.d)

let compare a b = ncmp (nmul a.n b.d) (nmul b.n a.d)

let sub a b =
  let x = nmul a.n b.d and y = nmul b.n a.d in
  if ncmp x y < 0 then raise (Negative "sub") else make (nsub x y) (nmul a.d b.d)

let mul a b =
  if is_zero a || is_zero b then zero
  else
    (* cross-reduce first: the factors stay small *)
    let g1 = ngcd a.n b.d and g2 = ngcd b.n a.d in
    let q x g = fst (ndivmod x g) in
    { n = nmul (q a.n g1) (q b.n g2); d = nmul (q a.d g2) (q b.d g1) }

let div a b =
  if is_zero b then invalid_arg "Rat.div by zero"
  else mul a { n = b.d; d = b.n }

let of_decimal s =
  let len = String.length s in
  let is_digit c = c >= '0' && c <= '9' in
  let (mant, ex) = match String.index_opt (String.lowercase_ascii s) 'e' with
    | Some i -> (String.sub s 0 i, Some (String.sub s (i + 1) (len - i - 1)))
    | None -> (s, None) in
  let (ip, fp) = match String.index_opt mant '.' with
    | Some i -> (String.sub mant 0 i, String.sub mant (i + 1) (String.length mant - i - 1))
    | None -> (mant, "") in
  let ok_digits x = String.for_all is_digit x in
  let exp = match ex with
    | None -> Some 0
    | Some e ->
      let e' = if String.length e > 0 && e.[0] = '+' then String.sub e 1 (String.length e - 1) else e in
      if e' = "" then None
      else if e'.[0] = '-' then
        (let r = String.sub e' 1 (String.length e' - 1) in
         if r <> "" && ok_digits r then Some (- int_of_string r) else None)
      else if ok_digits e' then Some (int_of_string e') else None in
  match exp with
  | Some e when (ip <> "" || fp <> "") && ok_digits ip && ok_digits fp ->
    let digits = nof_digits (ip ^ fp) in
    let e = e - String.length fp in
    Some (if e >= 0 then make (nmul digits (npow10 e)) (nof_int 1)
          else make digits (npow10 (- e)))
  | _ -> None

(* spec/16 §6.4: the shortest of %.15g, %.16g, %.17g that round-trips to
   the same binary64 — Python's repr *)
let shortest x =
  let rec go p =
    let s = Printf.sprintf "%.*g" p x in
    if p >= 17 || float_of_string s = x then s else go (p + 1) in
  go 15

let of_float x =
  if not (Float.is_finite x) || x < 0.0 then None
  else of_decimal (shortest x)

let to_string a = nto_string a.n ^ "/" ^ nto_string a.d

let to_float a =
  if is_zero a then 0.0
  else begin
    let kb = nbits a.n - nbits a.d in
    let s = 55 - kb in
    let (num, den) = if s >= 0 then (nshl a.n s, a.d) else (a.n, nshl a.d (- s)) in
    let (m, r) = ndivmod num den in
    let m = nto_int m in                               (* in [2^54, 2^56) *)
    let tb = let k = ref 0 in while m lsr !k > 0 do incr k done; !k in
    let shift = tb - 53 in
    let mant = m lsr shift and rem = m land ((1 lsl shift) - 1) in
    let half = 1 lsl (shift - 1) in
    let up = rem > half || (rem = half && (Array.length r > 0 || mant land 1 = 1)) in
    Float.ldexp (float_of_int (if up then mant + 1 else mant)) (shift - s)
  end

let den_bits a = nbits a.d
let den_digits a = String.length (nto_string a.d)
