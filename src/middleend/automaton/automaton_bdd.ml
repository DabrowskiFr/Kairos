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
open Fo_atoms
open Automaton_config
open Automaton_types
open Ltl_valuation

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
    (List.length (Automaton_naive.all_valuations names)) (List.length vals) (List.length by_var);
  vals

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
