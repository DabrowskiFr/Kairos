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
open Automaton_core
open Fo_specs

let rec simplify_temporal_idempotence (f : fo_ltl) : fo_ltl =
  match f with
  | LTrue | LFalse | LAtom _ -> f
  | LNot a -> LNot (simplify_temporal_idempotence a)
  | LX a -> LX (simplify_temporal_idempotence a)
  | LG a -> begin
      match simplify_temporal_idempotence a with
      | LG b -> LG b
      | a' -> LG a'
    end
  | LAnd (a, b) -> LAnd (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LOr (a, b) -> LOr (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LImp (a, b) -> LImp (simplify_temporal_idempotence a, simplify_temporal_idempotence b)

let build_monitor_spec ~(atom_map : (fo * ident) list) (n : Ast.node) : fo_ltl =
  let _ = atom_map in
  let spec_assumes = n.assumes in
  let spec_guarantees = n.guarantees in
  combine_contracts_for_monitor ~assumes:spec_assumes ~guarantees:spec_guarantees
  |> simplify_temporal_idempotence
  |> simplify_ltl
