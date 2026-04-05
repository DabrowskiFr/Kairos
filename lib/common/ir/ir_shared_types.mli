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

(** Shared type aliases used by IR-facing interfaces.

    This module provides a stable surface for common structural types used by
    the IR, while keeping compatibility with the current AST definitions. *)

type ident = Ast.ident
type loc = Ast.loc
type ltl = Ast.ltl
type ltl_o = Ast.ltl_o
type hexpr = Ast.hexpr
type iexpr = Ast.iexpr
type stmt = Ast.stmt
type vdecl = Ast.vdecl
type invariant_user = Ast.invariant_user
type invariant_state_rel = Ast.invariant_state_rel

(** Stable identifier attached to logical formulas across exports/reports. *)
type formula_id = int

(** Index of a transition inside a node transition table. *)
type transition_index = int

(** Index of an automaton state in generated assume/guarantee automata. *)
type automaton_state_index = int

(** Entry mapping a formula id to its optional origin metadata. *)
type formula_origin_entry = formula_id * Formula_origin.t option
