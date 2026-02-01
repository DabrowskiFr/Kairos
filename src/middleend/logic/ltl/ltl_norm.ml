(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
 * Copyright (C) 2026 Frederic Dabrowski
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

let rec nnf_ltl ?(neg=false) (f:fo_ltl) : fo_ltl =
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

let rec simplify_ltl (f:fo_ltl) : fo_ltl =
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
