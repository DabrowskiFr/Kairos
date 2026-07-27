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

(** Pure preparation of temporal contracts for automata production.

    This module validates the supported temporal fragment, normalizes the
    formulas and establishes the stable atom mapping. It does not depend on an
    automata protocol or invoke an external tool. *)

type atom_map =
  (Core_syntax.ltl_atom * Core_syntax.ident) list

type prepared_formula = {
  formula : Core_syntax.ltl;
  atoms : atom_map;
}

type prepared_node = {
  node_name : Core_syntax.ident;
  guarantee : prepared_formula;
  assumption : prepared_formula option;
}

val prepare_node :
  Verification_model.node_model ->
  (prepared_node, string) result

val prepare_program :
  Verification_model.program_model ->
  (prepared_node list, string) result
