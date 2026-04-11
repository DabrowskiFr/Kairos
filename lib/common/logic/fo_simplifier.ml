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

open Core_syntax
open Ast
module Solver = Fo_z3_solver
open Temporal_support

let rec simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  match Solver.simplify_fo_formula f with Some g -> g | None -> f

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
