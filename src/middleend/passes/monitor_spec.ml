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
open Automaton_core
open Fo_specs

let build_monitor_spec ~(atom_map:(fo * ident) list) (n:node) : ltl =
  let spec_assumes = List.map (replace_atoms_ltl atom_map) n.assumes in
  let spec_guarantees = List.map (replace_atoms_ltl atom_map) n.guarantees in
  combine_contracts_for_monitor ~assumes:spec_assumes ~guarantees:spec_guarantees
  |> simplify_ltl
