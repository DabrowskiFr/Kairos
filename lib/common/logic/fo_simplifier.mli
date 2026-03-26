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

(** Simplification routines for first-order and temporal formulas used across
    automata, kernel IR, and Why generation. *)

(** Simplify a non-temporal boolean formula using local rewrites plus optional
    Z3 checks. *)
val simplify_fo : Fo_formula.t -> Fo_formula.t

(** Simplify an LTL formula while preserving temporal operators. *)
val simplify_ltl : Ast.ltl -> Ast.ltl
