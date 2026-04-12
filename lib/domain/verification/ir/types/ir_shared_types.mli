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

type ident = Core_syntax.ident
(** Type [loc]. *)

type loc = Loc.loc
(** Type [ltl]. *)

type ltl = Core_syntax.ltl
(** Type [ltl_o]. *)

type ltl_o = Core_syntax.ltl_o
(** Type [hexpr]. *)

type hexpr = Core_syntax.hexpr
(** Type [expr]. *)

type expr = Core_syntax.expr
(** Type [stmt]. *)

type stmt = Ast.stmt
(** Type [vdecl]. *)

type vdecl = Core_syntax.vdecl

(** Stable identifier attached to logical formulas across exports/reports. *)
type formula_id = int

(** Index of a transition inside a node transition table. *)
type transition_index = int

(** Index of an automaton state in generated assume/guarantee automata. *)
type automaton_state_index = int
