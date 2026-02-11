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

open Ltl_valuation

type guard = Automaton_types.guard

let guard_is_true (g : guard) : bool =
  List.exists (fun t -> List.for_all (fun (_, v) -> v = None) t) g

let guard_to_formula (g : guard) : string =
  match g with
  | [] -> "false"
  | _ when guard_is_true g -> "true"
  | _ -> (
      let parts = List.map term_to_string g in
      match parts with [] -> "false" | [ p ] -> p | _ -> String.concat " || " parts)

let guard_to_iexpr (g : guard) : Ast.iexpr = terms_to_iexpr g |> simplify_iexpr
