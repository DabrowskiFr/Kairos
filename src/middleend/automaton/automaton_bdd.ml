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
