(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
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

(** Static availability analysis for historical reads.

    A historical read [pre_k(x,k)] is source-level meaningful only at points
    where at least [k] completed instants are available.  This module computes
    the required history depth of formulas and a conservative control-flow
    lower bound on the number of completed instants available at each state.

    Architecturally, this is the OCaml-side witness for the Rocq
    [InitializationFrontier] contract:

    {[
      available(point, formula) ->
      required_depth(formula) <= age(point)
    ]}

    The Rocq development formalizes that contract and the semantic
    extensionality of initialized historical formulas.  It does not certify
    this module's graph algorithm. *)

val required_depth_hexpr : 'phase Core_syntax.hexpr -> int

val required_depth_ltl : Core_syntax.ltl -> int

val min_ticks_by_state :
  Verification_model.node_model -> (Core_syntax.ident * int option) list

val min_ticks_for_state :
  (Core_syntax.ident * int option) list -> Core_syntax.ident -> int option
