(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
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
module Solver = Fo_z3_solver
open Temporal_support
open Fo_formula

let rec flatten_and acc = function
  | FAnd (a, b) -> flatten_and (flatten_and acc a) b
  | x -> x :: acc

let rec flatten_or acc = function
  | FOr (a, b) -> flatten_or (flatten_or acc a) b
  | x -> x :: acc

let rebuild_and = function
  | [] -> FTrue
  | [ x ] -> x
  | x :: xs -> List.fold_left (fun acc y -> FAnd (acc, y)) x xs

let rebuild_or = function
  | [] -> FFalse
  | [ x ] -> x
  | x :: xs -> List.fold_left (fun acc y -> FOr (acc, y)) x xs

let syntactic_rel_simplify = function
  | FAtom (FRel (h1, REq, h2)) when h1 = h2 -> Some FTrue
  | FAtom (FRel (h1, RNeq, h2)) when h1 = h2 -> Some FFalse
  | _ -> None

let simplify_and_parts (parts : Fo_formula.t list) : Fo_formula.t =
  let rec loop acc = function
    | [] -> rebuild_and (List.rev acc)
    | x :: xs when x = FTrue -> loop acc xs
    | x :: _ when x = FFalse -> FFalse
    | x :: xs when List.exists (( = ) x) acc -> loop acc xs
    | x :: xs ->
        if List.exists (fun y -> Solver.implies_formula (ltl_of_fo y) (ltl_of_fo x) = Some true) acc
        then loop acc xs
        else
          let acc =
            List.filter (fun y -> Solver.implies_formula (ltl_of_fo x) (ltl_of_fo y) <> Some true) acc
          in
          loop (x :: acc) xs
  in
  loop [] parts

let simplify_or_parts (parts : Fo_formula.t list) : Fo_formula.t =
  let rec loop acc = function
    | [] -> rebuild_or (List.rev acc)
    | x :: xs when x = FFalse -> loop acc xs
    | x :: _ when x = FTrue -> FTrue
    | x :: xs when List.exists (( = ) x) acc -> loop acc xs
    | x :: xs ->
        if List.exists (fun y -> Solver.implies_formula (ltl_of_fo x) (ltl_of_fo y) = Some true) acc
        then loop acc xs
        else
          let acc =
            List.filter (fun y -> Solver.implies_formula (ltl_of_fo y) (ltl_of_fo x) <> Some true) acc
          in
          loop (x :: acc) xs
  in
  loop [] parts

let rec simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  let rec go = function
    | FTrue | FFalse as f -> f
    | FAtom _ as f -> begin match syntactic_rel_simplify f with Some g -> g | None -> f end
    | FNot a -> begin
        match go a with
        | FTrue -> FFalse
        | FFalse -> FTrue
        | FNot b -> b
        | a' ->
            let f' = FNot a' in
            if Solver.solver_enabled () then
              match (Solver.prove_formula (ltl_of_fo f'), Solver.unsat_formula (ltl_of_fo f')) with
              | Some true, _ -> FTrue
              | _, Some true -> FFalse
              | _ -> f'
            else f'
      end
    | FAnd _ as f ->
        let parts = flatten_and [] f |> List.map go in
        let f' = simplify_and_parts parts in
        if Solver.solver_enabled () then
          match (Solver.prove_formula (ltl_of_fo f'), Solver.unsat_formula (ltl_of_fo f')) with
          | Some true, _ -> FTrue
          | _, Some true -> FFalse
          | _ -> f'
        else f'
    | FOr _ as f ->
        let parts = flatten_or [] f |> List.map go in
        let f' = simplify_or_parts parts in
        if Solver.solver_enabled () then
          match (Solver.prove_formula (ltl_of_fo f'), Solver.unsat_formula (ltl_of_fo f')) with
          | Some true, _ -> FTrue
          | _, Some true -> FFalse
          | _ -> f'
        else f'
    | FImp (a, b) ->
        let a = go a in
        let b = go b in
        let f' =
          match (a, b) with
          | FFalse, _ | _, FTrue -> FTrue
          | FTrue, x -> x
          | x, FFalse -> go (FNot x)
          | _ when a = b -> FTrue
          | _ ->
              if Solver.solver_enabled ()
                 && Solver.implies_formula (ltl_of_fo a) (ltl_of_fo b) = Some true
              then FTrue
              else FImp (a, b)
        in
        if Solver.solver_enabled () then
          match (Solver.prove_formula (ltl_of_fo f'), Solver.unsat_formula (ltl_of_fo f')) with
          | Some true, _ -> FTrue
          | _, Some true -> FFalse
          | _ -> f'
        else f'
  in
  go f

let rec simplify_ltl (f : ltl) : ltl =
  match f with
  | LTrue | LFalse | LAtom _ -> f
  | LNot a -> (
      match simplify_ltl a with
      | LTrue -> LFalse
      | LFalse -> LTrue
      | a' -> LNot a')
  | LAnd (a, b) -> (
      match (simplify_ltl a, simplify_ltl b) with
      | LTrue, x | x, LTrue -> x
      | LFalse, _ | _, LFalse -> LFalse
      | a', b' when a' = b' -> a'
      | a', b' -> LAnd (a', b'))
  | LOr (a, b) -> (
      match (simplify_ltl a, simplify_ltl b) with
      | LFalse, x | x, LFalse -> x
      | LTrue, _ | _, LTrue -> LTrue
      | a', b' when a' = b' -> a'
      | a', b' -> LOr (a', b'))
  | LImp (a, b) -> (
      match (simplify_ltl a, simplify_ltl b) with
      | LFalse, _ | _, LTrue -> LTrue
      | LTrue, x -> x
      | a', b' when a' = b' -> LTrue
      | a', b' -> LImp (a', b'))
  | LX a -> LX (simplify_ltl a)
  | LG a -> LG (simplify_ltl a)
  | LW (a, b) -> LW (simplify_ltl a, simplify_ltl b)
