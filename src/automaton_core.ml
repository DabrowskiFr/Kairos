(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Ast

let escape_dot_label (s:string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let monitor_log_enabled : bool =
  match Sys.getenv_opt "OBCWHY3_LOG_MONITOR" with
  | Some ("1" | "true" | "yes") -> true
  | _ -> false

let log_monitor fmt =
  Printf.ksprintf
    (fun s ->
       if monitor_log_enabled then
         prerr_endline ("[monitor] " ^ s))
    fmt

let all_valuations (names:string list) : (string * bool) list list =
  let rec aux acc = function
    | [] -> [List.rev acc]
    | n :: rest ->
        let t = aux ((n, true) :: acc) rest in
        let f = aux ((n, false) :: acc) rest in
        t @ f
  in
  aux [] names

type eq_value =
  | VInt of int
  | VBool of bool

type eq_atom = {
  name: string;
  var: string;
  value: eq_value;
}

let extract_eq_atom ((f, name):(fo * ident)) : eq_atom option =
  let mk var value = Some { name; var; value } in
  match f with
  | FRel (HNow (IVar x), REq, HNow (ILitInt i)) -> mk x (VInt i)
  | FRel (HNow (ILitInt i), REq, HNow (IVar x)) -> mk x (VInt i)
  | FRel (HNow (IVar x), REq, HNow (ILitBool b)) -> mk x (VBool b)
  | FRel (HNow (ILitBool b), REq, HNow (IVar x)) -> mk x (VBool b)
  | _ -> None

let constrained_valuations (atom_map:(fo * ident) list) (names:string list)
  : (string * bool) list list =
  let raw = all_valuations names in
  let eq_atoms = List.filter_map extract_eq_atom atom_map in
  let by_var =
    List.fold_left
      (fun acc a ->
         let existing = List.assoc_opt a.var acc |> Option.value ~default:[] in
         (a.var, a :: existing)
         :: List.remove_assoc a.var acc)
      []
      eq_atoms
  in
  let consistent vals =
    let lookup name =
      match List.assoc_opt name vals with
      | Some true -> true
      | _ -> false
    in
    let check_var atoms =
      let bool_true = List.find_opt (fun a -> a.value = VBool true) atoms in
      let bool_false = List.find_opt (fun a -> a.value = VBool false) atoms in
      match bool_true, bool_false with
      | Some t, Some f ->
          let vt = lookup t.name in
          let vf = lookup f.name in
          (vt && not vf) || (vf && not vt)
      | _ ->
          let trues =
            List.fold_left
              (fun acc a -> if lookup a.name then acc + 1 else acc)
              0
              atoms
          in
          trues <= 1
    in
    List.for_all (fun (_var, atoms) -> check_var atoms) by_var
  in
  let filtered = List.filter consistent raw in
  log_monitor "valuations: raw=%d filtered=%d constraints=%d"
    (List.length raw) (List.length filtered) (List.length by_var);
  filtered

type bdd_node = {
  bdd_var: int;
  bdd_low: int;
  bdd_high: int;
}

let bdd_false = 0
let bdd_true = 1

let bdd_nodes : (int, bdd_node) Hashtbl.t = Hashtbl.create 128
let bdd_unique : (int * int * int, int) Hashtbl.t = Hashtbl.create 128
let bdd_next = ref 2

let bdd_mk (var:int) (low:int) (high:int) : int =
  if low = high then low
  else
    match Hashtbl.find_opt bdd_unique (var, low, high) with
    | Some id -> id
    | None ->
        let id = !bdd_next in
        incr bdd_next;
        Hashtbl.add bdd_nodes id { bdd_var = var; bdd_low = low; bdd_high = high };
        Hashtbl.add bdd_unique (var, low, high) id;
        id

let bdd_var (i:int) : int = bdd_mk i bdd_false bdd_true

let bdd_not (a:int) : int =
  let memo = Hashtbl.create 128 in
  let rec go n =
    if n = bdd_false then bdd_true
    else if n = bdd_true then bdd_false
    else
      match Hashtbl.find_opt memo n with
      | Some v -> v
      | None ->
          let node = Hashtbl.find bdd_nodes n in
          let low = go node.bdd_low in
          let high = go node.bdd_high in
          let res = bdd_mk node.bdd_var low high in
          Hashtbl.add memo n res;
          res
  in
  go a

let bdd_apply (op:bool -> bool -> bool) (a:int) (b:int) : int =
  let memo = Hashtbl.create 256 in
  let rec go x y =
    if x = bdd_false && y = bdd_false then if op false false then bdd_true else bdd_false
    else if x = bdd_false && y = bdd_true then if op false true then bdd_true else bdd_false
    else if x = bdd_true && y = bdd_false then if op true false then bdd_true else bdd_false
    else if x = bdd_true && y = bdd_true then if op true true then bdd_true else bdd_false
    else
      match Hashtbl.find_opt memo (x, y) with
      | Some v -> v
      | None ->
          let vx = if x <= 1 then max_int else (Hashtbl.find bdd_nodes x).bdd_var in
          let vy = if y <= 1 then max_int else (Hashtbl.find bdd_nodes y).bdd_var in
          let v = min vx vy in
          let xl, xh =
            if vx = v then
              let n = Hashtbl.find bdd_nodes x in (n.bdd_low, n.bdd_high)
            else
              (x, x)
          in
          let yl, yh =
            if vy = v then
              let n = Hashtbl.find bdd_nodes y in (n.bdd_low, n.bdd_high)
            else
              (y, y)
          in
          let low = go xl yl in
          let high = go xh yh in
          let res = bdd_mk v low high in
          Hashtbl.add memo (x, y) res;
          res
  in
  go a b

let bdd_and a b = bdd_apply (fun x y -> x && y) a b
let bdd_or a b = bdd_apply (fun x y -> x || y) a b

let bdd_exactly_one (vars:int list) : int =
  let rec pairwise_not acc = function
    | [] -> acc
    | v :: rest ->
        let acc =
          List.fold_left
            (fun acc u ->
               let both = bdd_and (bdd_var v) (bdd_var u) in
               bdd_and acc (bdd_not both))
            acc
            rest
        in
        pairwise_not acc rest
  in
  let at_least_one =
    List.fold_left (fun acc v -> bdd_or acc (bdd_var v)) bdd_false vars
  in
  let at_most_one = pairwise_not bdd_true vars in
  bdd_and at_least_one at_most_one

let bdd_at_most_one (vars:int list) : int =
  let rec pairwise_not acc = function
    | [] -> acc
    | v :: rest ->
        let acc =
          List.fold_left
            (fun acc u ->
               let both = bdd_and (bdd_var v) (bdd_var u) in
               bdd_and acc (bdd_not both))
            acc
            rest
        in
        pairwise_not acc rest
  in
  pairwise_not bdd_true vars

let bdd_valuations (atom_map:(fo * ident) list) (names:string list)
  : (string * bool) list list =
  let index_of name =
    let rec loop i = function
      | [] -> None
      | x :: xs -> if x = name then Some i else loop (i + 1) xs
    in
    loop 0 names
  in
  let eq_atoms = List.filter_map extract_eq_atom atom_map in
  let by_var =
    List.fold_left
      (fun acc a ->
         let existing = List.assoc_opt a.var acc |> Option.value ~default:[] in
         (a.var, a :: existing)
         :: List.remove_assoc a.var acc)
      []
      eq_atoms
  in
  let constraints =
    List.map
      (fun (_var, atoms) ->
         let indexed =
           List.filter_map
             (fun a ->
                match index_of a.name with
                | None -> None
                | Some i -> Some (a.value, i))
             atoms
         in
         let bool_true = List.exists (fun (v, _) -> v = VBool true) indexed in
         let bool_false = List.exists (fun (v, _) -> v = VBool false) indexed in
         let vars = List.map snd indexed in
         if bool_true && bool_false then bdd_exactly_one vars
         else bdd_at_most_one vars)
      by_var
  in
  let constraint_bdd = List.fold_left bdd_and bdd_true constraints in
  let rec expand_rest i =
    if i >= List.length names then [ [] ]
    else
      let tail = expand_rest (i + 1) in
      List.concat_map
        (fun acc -> [ (List.nth names i, false) :: acc; (List.nth names i, true) :: acc ])
        tail
  in
  let rec enumerate node idx =
    if node = bdd_false then []
    else if node = bdd_true then
      List.map List.rev (expand_rest idx)
    else
      let n = Hashtbl.find bdd_nodes node in
      let rec fill_until i =
        if i >= n.bdd_var then [ [] ]
        else
          let tails = fill_until (i + 1) in
          List.concat_map
            (fun acc -> [ (List.nth names i, false) :: acc; (List.nth names i, true) :: acc ])
            tails
      in
      let prefix = fill_until idx in
      let low_vals = enumerate n.bdd_low (n.bdd_var + 1) in
      let high_vals = enumerate n.bdd_high (n.bdd_var + 1) in
      let with_low =
        List.concat_map
          (fun pre ->
             List.map (fun tail -> List.rev_append tail ((List.nth names n.bdd_var, false) :: pre)) low_vals)
          prefix
      in
      let with_high =
        List.concat_map
          (fun pre ->
             List.map (fun tail -> List.rev_append tail ((List.nth names n.bdd_var, true) :: pre)) high_vals)
          prefix
      in
      with_low @ with_high
  in
  let vals = enumerate constraint_bdd 0 in
  log_monitor "valuations: raw=%d bdd=%d constraints=%d"
    (List.length (all_valuations names)) (List.length vals) (List.length by_var);
  vals

let naive_automaton = ref false

let set_naive_automaton (flag:bool) : unit =
  naive_automaton := flag

let enumerate_valuations (atom_map:(fo * ident) list) (names:string list)
  : (string * bool) list list =
  if !naive_automaton then
    all_valuations names
  else
    bdd_valuations atom_map names

let valuation_label (vals:(string * bool) list) : string =
  vals
  |> List.map (fun (n,b) -> n ^ "=" ^ (if b then "1" else "0"))
  |> String.concat ","

type term = (string * bool option) list

let lookup_val (vals:(string * bool) list) (name:string) : bool =
  match List.assoc_opt name vals with
  | Some b -> b
  | None -> false

let term_of_vals (atom_names:string list) (vals:(string * bool) list) : term =
  List.map (fun name -> (name, Some (lookup_val vals name))) atom_names

let can_merge_terms (t1:term) (t2:term) : bool =
  let diff = ref 0 in
  let rec loop = function
    | [], [] -> !diff = 1
    | (_, v1) :: r1, (_, v2) :: r2 ->
        begin match v1, v2 with
        | Some b1, Some b2 when b1 = b2 -> loop (r1, r2)
        | Some _, Some _ ->
            incr diff;
            !diff <= 1 && loop (r1, r2)
        | None, None -> loop (r1, r2)
        | None, Some _ | Some _, None -> false
        end
    | _ -> false
  in
  loop (t1, t2)

let merge_terms (t1:term) (t2:term) : term =
  List.map2
    (fun (n1, v1) (_n2, v2) ->
       let v =
         match v1, v2 with
         | Some b1, Some b2 when b1 = b2 -> Some b1
         | Some _, Some _ -> None
         | None, None -> None
         | None, Some b | Some b, None -> Some b
       in
       (n1, v))
    t1 t2

let uniq_terms (terms:term list) : term list =
  let rec loop acc = function
    | [] -> List.rev acc
    | t :: rest -> if List.exists ((=) t) acc then loop acc rest else loop (t :: acc) rest
  in
  loop [] terms

let prime_implicants (terms:term list) : term list =
  let rec loop terms primes =
    let terms = uniq_terms terms in
    let n = List.length terms in
    let used = Array.make n false in
    let merged = ref [] in
    for i = 0 to n - 1 do
      for j = i + 1 to n - 1 do
        let ti = List.nth terms i in
        let tj = List.nth terms j in
        if can_merge_terms ti tj then (
          used.(i) <- true;
          used.(j) <- true;
          merged := merge_terms ti tj :: !merged
        )
      done
    done;
    let new_primes =
      List.fold_left
        (fun acc (i, t) -> if used.(i) then acc else t :: acc)
        primes
        (List.mapi (fun i t -> (i, t)) terms)
    in
    if !merged = [] then uniq_terms new_primes
    else loop !merged new_primes
  in
  loop terms []

let term_covers (term:term) (vals:(string * bool) list) : bool =
  List.for_all
    (fun (name, v) ->
       match v with
       | None -> true
       | Some b -> lookup_val vals name = b)
    term

let choose_implicants (atom_names:string list) (vals_list:(string * bool) list list)
  : term list =
  if vals_list = [] then []
  else
    let minterms = List.map (term_of_vals atom_names) vals_list in
    let primes = prime_implicants minterms in
    let remaining = ref vals_list in
    let chosen = ref [] in
    let cover_count term =
      List.fold_left
        (fun acc vals -> if term_covers term vals then acc + 1 else acc)
        0
        !remaining
    in
    let rec loop () =
      let unique_cover =
        List.find_map
          (fun vals ->
             let covering = List.filter (fun t -> term_covers t vals) primes in
             match covering with
             | [t] -> Some t
             | _ -> None)
          !remaining
      in
      begin match unique_cover with
      | Some t ->
          if not (List.exists ((=) t) !chosen) then chosen := t :: !chosen;
          remaining := List.filter (fun v -> not (term_covers t v)) !remaining;
          if !remaining <> [] then loop ()
      | None ->
          if !remaining <> [] then (
            let t =
              List.fold_left
                (fun best cand ->
                   if cover_count cand > cover_count best then cand else best)
                (List.hd primes)
                primes
            in
            if not (List.exists ((=) t) !chosen) then chosen := t :: !chosen;
            remaining := List.filter (fun v -> not (term_covers t v)) !remaining;
            if !remaining <> [] then loop ()
          )
      end
    in
    loop ();
    uniq_terms !chosen

let term_to_string (term:term) : string =
  let parts =
    List.filter_map
      (fun (name, v) ->
         match v with
         | None -> None
         | Some true -> Some name
         | Some false -> Some ("not " ^ name))
      term
  in
  match parts with
  | [] -> "true"
  | _ -> String.concat " && " parts

let valuations_to_formula (atom_names:string list) (vals_list:(string * bool) list list)
  : string =
  match vals_list with
  | [] -> "false"
  | _ ->
      let implicants = choose_implicants atom_names vals_list in
      if List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) implicants then
        "true"
      else
        let parts = List.map term_to_string implicants in
        match parts with
        | [] -> "false"
        | [p] -> p
        | _ -> String.concat " || " parts

let term_to_iexpr (term:term) : iexpr =
  let parts =
    List.filter_map
      (fun (name, v) ->
         match v with
         | None -> None
         | Some true -> Some (IVar name)
         | Some false -> Some (IUn (Not, IVar name)))
      term
  in
  match parts with
  | [] -> ILitBool true
  | [p] -> p
  | p :: rest -> List.fold_left (fun acc x -> IBin (And, acc, x)) p rest

let terms_to_iexpr (terms:term list) : iexpr =
  match terms with
  | [] -> ILitBool false
  | _ ->
      if List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) terms then
        ILitBool true
      else
        let parts = List.map term_to_iexpr terms in
        match parts with
        | [] -> ILitBool false
        | [p] -> p
        | p :: rest -> List.fold_left (fun acc x -> IBin (Or, acc, x)) p rest

let rec simplify_iexpr (e:iexpr) : iexpr =
  let is_negation a b =
    match a, b with
    | IUn (Not, x), y | x, IUn (Not, y) -> x = y
    | _ -> false
  in
  match e with
  | ILitInt _ | ILitBool _ | IVar _ -> e
  | IUn (Not, x) ->
      begin match simplify_iexpr x with
      | ILitBool true -> ILitBool false
      | ILitBool false -> ILitBool true
      | IUn (Not, y) -> y
      | y -> IUn (Not, y)
      end
  | IUn (op, x) ->
      IUn (op, simplify_iexpr x)
  | IBin (And, a, b) ->
      let a = simplify_iexpr a in
      let b = simplify_iexpr b in
      if a = ILitBool false || b = ILitBool false then ILitBool false
      else if a = ILitBool true then b
      else if b = ILitBool true then a
      else if a = b then a
      else if is_negation a b then ILitBool false
      else IBin (And, a, b)
  | IBin (Or, a, b) ->
      let a = simplify_iexpr a in
      let b = simplify_iexpr b in
      if a = ILitBool true || b = ILitBool true then ILitBool true
      else if a = ILitBool false then b
      else if b = ILitBool false then a
      else if a = b then a
      else if is_negation a b then ILitBool true
      else IBin (Or, a, b)
  | IBin (op, a, b) ->
      let a = simplify_iexpr a in
      let b = simplify_iexpr b in
      IBin (op, a, b)
  | IPar x -> IPar (simplify_iexpr x)

let valuations_to_iexpr (atom_names:string list) (vals_list:(string * bool) list list)
  : iexpr =
  match vals_list with
  | [] -> ILitBool false
  | _ ->
      let implicants = choose_implicants atom_names vals_list in
      terms_to_iexpr implicants

let empty_term (atom_names:string list) : term =
  List.map (fun name -> (name, None)) atom_names

let set_term (name:string) (value:bool) (t:term) : term =
  List.map (fun (n, v) -> if n = name then (n, Some value) else (n, v)) t

let bdd_to_terms (atom_names:string list) (node:int) : term list =
  let memo = Hashtbl.create 64 in
  let rec go n =
    match Hashtbl.find_opt memo n with
    | Some res -> res
    | None ->
        let res =
          if n = bdd_false then []
          else if n = bdd_true then [empty_term atom_names]
          else
            let node = Hashtbl.find bdd_nodes n in
            let name = List.nth atom_names node.bdd_var in
            let low_terms = List.map (set_term name false) (go node.bdd_low) in
            let high_terms = List.map (set_term name true) (go node.bdd_high) in
            low_terms @ high_terms
        in
        Hashtbl.add memo n res;
        res
  in
  go node

let term_covers_term (t1:term) (t2:term) : bool =
  List.for_all
    (fun ((_, v1), (_, v2)) ->
       match v1 with
       | None -> true
       | Some b1 -> v2 = Some b1)
    (List.combine t1 t2)

let simplify_terms (terms:term list) : term list =
  let terms = uniq_terms terms in
  List.filter
    (fun t ->
       not (List.exists (fun other -> other <> t && term_covers_term other t) terms))
    terms

let bdd_to_formula (atom_names:string list) (node:int) : string =
  let terms = bdd_to_terms atom_names node |> simplify_terms in
  if List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) terms then
    "true"
  else
    let parts = List.map term_to_string terms in
    match parts with
    | [] -> "false"
    | [p] -> p
    | _ -> String.concat " || " parts

let bdd_to_iexpr (atom_names:string list) (node:int) : iexpr =
  let terms = bdd_to_terms atom_names node |> simplify_terms in
  simplify_iexpr (terms_to_iexpr terms)

let rec nnf_ltl ?(neg=false) (f:ltl) : ltl =
  match f with
  | LTrue -> if neg then LFalse else LTrue
  | LFalse -> if neg then LTrue else LFalse
  | LAtom a -> if neg then LNot (LAtom a) else LAtom a
  | LNot a -> nnf_ltl ~neg:(not neg) a
  | LAnd (a,b) ->
      if neg then LOr (nnf_ltl ~neg:true a, nnf_ltl ~neg:true b)
      else LAnd (nnf_ltl a, nnf_ltl b)
  | LOr (a,b) ->
      if neg then LAnd (nnf_ltl ~neg:true a, nnf_ltl ~neg:true b)
      else LOr (nnf_ltl a, nnf_ltl b)
  | LImp (a,b) ->
      nnf_ltl ~neg (LOr (LNot a, b))
  | LX a ->
      if neg then LX (nnf_ltl ~neg:true a) else LX (nnf_ltl a)
  | LG a ->
      if neg then
        let msg =
          "NNF: negation above G not supported in G/X fragment: not G("
          ^ Support.string_of_ltl a ^ ")"
        in
        failwith msg
      else
        LG (nnf_ltl a)

let rec simplify_ltl (f:ltl) : ltl =
  let sort_terms terms =
    let cmp a b =
      String.compare (Support.string_of_ltl a) (Support.string_of_ltl b)
    in
    List.sort cmp terms
  in
  let uniq_terms terms =
    let rec loop acc = function
      | [] -> List.rev acc
      | x :: xs -> if List.mem x acc then loop acc xs else loop (x :: acc) xs
    in
    loop [] terms
  in
  let rec flatten_and acc = function
    | LAnd (x, y) -> flatten_and (flatten_and acc x) y
    | LTrue -> acc
    | LFalse -> LFalse :: acc
    | x -> x :: acc
  in
  let rec flatten_or acc = function
    | LOr (x, y) -> flatten_or (flatten_or acc x) y
    | LFalse -> acc
    | LTrue -> LTrue :: acc
    | x -> x :: acc
  in
  let absorb_and parts =
    List.filter
      (function
        | LOr _ as t ->
            let ors = flatten_or [] t |> List.map simplify_ltl in
            not (List.exists (fun p -> List.mem p ors) parts)
        | _ -> true)
      parts
  in
  let absorb_or parts =
    List.filter
      (function
        | LAnd _ as t ->
            let ands = flatten_and [] t |> List.map simplify_ltl in
            not (List.exists (fun p -> List.mem p ands) parts)
        | _ -> true)
      parts
  in
  match f with
  | LAnd _ ->
      let parts = flatten_and [] f |> List.map simplify_ltl in
      if List.exists ((=) LFalse) parts then LFalse
      else
        let parts = List.filter (fun x -> x <> LTrue) parts in
        let parts = absorb_and parts |> uniq_terms |> sort_terms in
        begin match parts with
        | [] -> LTrue
        | [x] -> x
        | x :: xs -> List.fold_left (fun acc y -> LAnd (acc, y)) x xs
        end
  | LOr _ ->
      let parts = flatten_or [] f |> List.map simplify_ltl in
      if List.exists ((=) LTrue) parts then LTrue
      else
        let parts = List.filter (fun x -> x <> LFalse) parts in
        let parts = absorb_or parts |> uniq_terms |> sort_terms in
        begin match parts with
        | [] -> LFalse
        | [x] -> x
        | x :: xs -> List.fold_left (fun acc y -> LOr (acc, y)) x xs
        end
  | LImp (a,b) ->
      simplify_ltl (LOr (LNot a, b))
  | LNot a ->
      let a = simplify_ltl a in
      begin match a with
      | LTrue -> LFalse
      | LFalse -> LTrue
      | LNot b -> b
      | _ -> LNot a
      end
  | LG a -> LG (simplify_ltl a)
  | LX a -> LX (simplify_ltl a)
  | _ -> f

let eval_atom (_atom_map:(fo * ident) list) (vals:(string * bool) list) (f:fo)
  : bool =
  match f with
  | FRel (HNow (IVar name), REq, HNow (ILitBool true)) ->
      lookup_val vals name
  | _ -> false

let rec progress_ltl (atom_map:(fo * ident) list) (vals:(string * bool) list) (f:ltl)
  : ltl =
  let f =
    match f with
    | LTrue | LFalse -> f
    | LAtom a -> if eval_atom atom_map vals a then LTrue else LFalse
    | LNot a -> LNot (progress_ltl atom_map vals a)
    | LAnd (a,b) -> LAnd (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LOr (a,b) -> LOr (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LImp (a,b) -> LImp (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LX a -> a
    | LG a ->
        let a_now = progress_ltl atom_map vals a in
        LAnd (a_now, LG a)
  in
  simplify_ltl f

type residual_state = ltl

type residual_transition = int * (string * bool) list * int

type grouped_transition = int * (string * bool) list list * int

type guarded_transition = int * int * int

let build_residual_graph (atom_map:(fo * ident) list)
  (valuations:(string * bool) list list) (f0:ltl)
  : residual_state list * residual_transition list =
  let start_time = Sys.time () in
  let f0 = nnf_ltl f0 |> simplify_ltl in
  let tbl = Hashtbl.create 16 in
  let states = ref [] in
  let transitions = ref [] in
  let state_count = ref 0 in
  log_monitor "build residual graph: valuations=%d" (List.length valuations);
  let add_state f =
    let key = Support.string_of_ltl f in
    match Hashtbl.find_opt tbl key with
    | Some i -> (i, false)
    | None ->
        let i = List.length !states in
        states := !states @ [f];
        incr state_count;
        if !state_count mod 100 = 0 then
          log_monitor "states=%d transitions=%d"
            !state_count (List.length !transitions);
        if !state_count = 1000 || !state_count = 10000 then
          log_monitor "state threshold reached: %d" !state_count;
        Hashtbl.add tbl key i;
        (i, true)
  in
  let q = Queue.create () in
  let _ = add_state f0 in
  Queue.add f0 q;
  while not (Queue.is_empty q) do
    let f = Queue.take q in
    let i = Hashtbl.find tbl (Support.string_of_ltl f) in
    List.iter
      (fun vals ->
         let f' = progress_ltl atom_map vals f in
         let (j, is_new) = add_state f' in
         transitions := (i, vals, j) :: !transitions;
         if is_new then Queue.add f' q)
      valuations
  done;
  log_monitor "done: states=%d transitions=%d time=%.3fs"
    !state_count (List.length !transitions) (Sys.time () -. start_time);
  (!states, List.rev !transitions)

let group_transitions (transitions:residual_transition list)
  : grouped_transition list =
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (i, vals, j) ->
       let per_src =
         match Hashtbl.find_opt by_src i with
         | Some m -> m
         | None ->
             let m = Hashtbl.create 16 in
             Hashtbl.add by_src i m;
             m
       in
       let prev = Hashtbl.find_opt per_src j |> Option.value ~default:[] in
       Hashtbl.replace per_src j (vals :: prev))
    transitions;
  Hashtbl.fold
    (fun src per_src acc ->
       let items =
         Hashtbl.fold
           (fun dst vals_list acc -> (src, vals_list, dst) :: acc)
           per_src
           []
       in
       items @ acc)
    by_src
    []

let bdd_of_vals (index_tbl:(string, int) Hashtbl.t) (vals:(string * bool) list) : int =
  List.fold_left
    (fun acc (name, v) ->
       match Hashtbl.find_opt index_tbl name with
       | None -> acc
       | Some idx ->
           let lit = if v then bdd_var idx else bdd_not (bdd_var idx) in
           bdd_and acc lit)
    bdd_true
    vals

let group_transitions_bdd (atom_names:string list)
  (transitions:residual_transition list) : guarded_transition list =
  let index_tbl = Hashtbl.create 16 in
  List.iteri (fun i name -> Hashtbl.add index_tbl name i) atom_names;
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (i, vals, j) ->
       let per_src =
         match Hashtbl.find_opt by_src i with
         | Some m -> m
         | None ->
             let m = Hashtbl.create 16 in
             Hashtbl.add by_src i m;
             m
       in
       let guard = bdd_of_vals index_tbl vals in
       let prev = Hashtbl.find_opt per_src j |> Option.value ~default:bdd_false in
       Hashtbl.replace per_src j (bdd_or prev guard))
    transitions;
  Hashtbl.fold
    (fun src per_src acc ->
       let items =
         Hashtbl.fold
           (fun dst guard acc -> (src, guard, dst) :: acc)
           per_src
           []
       in
       items @ acc)
    by_src
    []

let minimize_residual_graph (valuations:(string * bool) list list)
  (states:residual_state list) (transitions:residual_transition list)
  : residual_state list * residual_transition list =
  let n_states = List.length states in
  let val_index =
    let tbl = Hashtbl.create 16 in
    List.iteri (fun i v -> Hashtbl.add tbl (valuation_label v) i) valuations;
    tbl
  in
  let n_inputs = List.length valuations in
  let delta = Array.make_matrix n_states n_inputs 0 in
  List.iter
    (fun (i, vals, j) ->
       let key = valuation_label vals in
       match Hashtbl.find_opt val_index key with
       | Some k -> delta.(i).(k) <- j
       | None -> ())
    transitions;
  let is_accept i =
    match List.nth states i with
    | LFalse -> false
    | _ -> true
  in
  let class_of = Array.make n_states 0 in
  for i = 0 to n_states - 1 do
    class_of.(i) <- if is_accept i then 1 else 0
  done;
  let rec refine () =
    let table = Hashtbl.create n_states in
    let next_class = Array.make n_states 0 in
    let next_id = ref 0 in
    for i = 0 to n_states - 1 do
      let buf = Buffer.create 32 in
      Buffer.add_string buf (if is_accept i then "1|" else "0|");
      for k = 0 to n_inputs - 1 do
        Buffer.add_string buf (string_of_int class_of.(delta.(i).(k)));
        Buffer.add_char buf ','
      done;
      let key = Buffer.contents buf in
      match Hashtbl.find_opt table key with
      | Some id -> next_class.(i) <- id
      | None ->
          let id = !next_id in
          incr next_id;
          Hashtbl.add table key id;
          next_class.(i) <- id
    done;
    let changed = ref false in
    for i = 0 to n_states - 1 do
      if next_class.(i) <> class_of.(i) then changed := true
    done;
    Array.blit next_class 0 class_of 0 n_states;
    if !changed then refine () else ()
  in
  refine ();
  let class_count =
    Array.fold_left (fun acc x -> max acc (x + 1)) 0 class_of
  in
  let rep = Array.make class_count (-1) in
  for i = 0 to n_states - 1 do
    let c = class_of.(i) in
    if rep.(c) = -1 then rep.(c) <- i
  done;
  let new_states =
    List.init class_count (fun c -> List.nth states rep.(c))
  in
  let new_transitions = ref [] in
  for c = 0 to class_count - 1 do
    let s = rep.(c) in
    for k = 0 to n_inputs - 1 do
      let t = delta.(s).(k) in
      let c' = class_of.(t) in
      let vals = List.nth valuations k in
      new_transitions := (c, vals, c') :: !new_transitions
    done
  done;
  (new_states, List.rev !new_transitions)
