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

(** Temporal rewriting helpers for FO formulas.

    These functions shift input-dependent history references forward/backward
    when moving formulas across tick boundaries in IR passes. *)

open Core_syntax
(** Time-shifting utilities for formulas and history expressions. *)

(** Shift one step forward all input-dependent references in a non-temporal
    boolean formula. *)
val shift_formula_forward_inputs :
  is_input:(ident -> bool) -> Core_syntax.hexpr -> Core_syntax.hexpr

(** Shift one step backward all input-dependent references in a non-temporal
    boolean formula. *)
val shift_formula_backward_inputs :
  is_input:(ident -> bool) -> Core_syntax.hexpr -> Core_syntax.hexpr
