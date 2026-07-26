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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Kairos-owned conversion to and from the neutral automata contract. *)

type atom_map = (Core_syntax.ltl_atom * Core_syntax.ident) list

val request_of_core :
  atom_map:atom_map -> Core_syntax.ltl -> Kairos_automata_contract.Automata_exchange.request

val automaton_of_response :
  atom_map:atom_map ->
  Kairos_automata_contract.Automata_exchange.response ->
  Automaton_types.automaton
