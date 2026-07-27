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

(** Protocol adaptation and external construction of prepared automata.

    Formula validation, normalization and atom preparation belong to
    {!Automata_preparation}. *)

val run :
  Verification_model.program_model ->
  build_automaton:
    (Kairos_automata_contract.Automata_exchange.request ->
    Kairos_automata_contract.Automata_exchange.response) ->
  ( (Core_syntax.ident * Automaton_types.automata_spec) list
    * Flow_info.automata_info,
    string )
  result
