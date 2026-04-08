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

(** Time-shifting utilities for formulas and history expressions. *)

(** Shift one step forward every historical occurrence whose underlying
    expression depends on an input. *)
val shift_fo_forward_inputs : is_input:(Ast.ident -> bool) -> Ast.fo_atom -> Ast.fo_atom

(** Shift one step backward every historical occurrence whose underlying
    expression depends on an input. *)
val shift_fo_backward_inputs : is_input:(Ast.ident -> bool) -> Ast.fo_atom -> Ast.fo_atom

(** Shift one step forward all input-dependent references in a non-temporal
    boolean formula. *)
val shift_formula_forward_inputs :
  is_input:(Ast.ident -> bool) -> Fo_formula.t -> Fo_formula.t

(** Shift one step backward all input-dependent references in a non-temporal
    boolean formula. *)
val shift_formula_backward_inputs :
  is_input:(Ast.ident -> bool) -> Fo_formula.t -> Fo_formula.t

(** Shift all references inside a first-order formula one step forward in
    time. *)
val shift_fo_forward_all : Ast.fo_atom -> Ast.fo_atom

(** Shift all references inside a first-order formula one step backward in
    time. *)
val shift_fo_backward_all : Ast.fo_atom -> Ast.fo_atom

(** Shift one step forward every historical occurrence whose underlying
    expression depends on an input. *)
val shift_ltl_forward_inputs : is_input:(Ast.ident -> bool) -> Ast.ltl -> Ast.ltl

(** Shift one step backward every historical occurrence whose underlying
    expression depends on an input.

    This is only a partial inverse of {!val-shift_ltl_forward_inputs}: a
    current input [HNow x] has no predecessor-time counterpart when moving
    from the beginning of tick [t+1] back to the end of tick [t], so such
    occurrences are rejected explicitly. *)
val shift_ltl_backward_inputs : is_input:(Ast.ident -> bool) -> Ast.ltl -> Ast.ltl
