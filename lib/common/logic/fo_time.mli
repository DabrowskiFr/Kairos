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

(** Shift input references inside a first-order formula one step forward in
    time. *)
val shift_fo_forward_inputs : is_input:(Ast.ident -> bool) -> Ast.fo_atom -> Ast.fo_atom

(** Shift input references inside a first-order formula one step backward in
    time. *)
val shift_fo_backward_inputs : is_input:(Ast.ident -> bool) -> Ast.fo_atom -> Ast.fo_atom

(** Shift all references inside a first-order formula one step forward in
    time. *)
val shift_fo_forward_all : Ast.fo_atom -> Ast.fo_atom

(** Shift all references inside a first-order formula one step backward in
    time. *)
val shift_fo_backward_all : Ast.fo_atom -> Ast.fo_atom

(** Shift input references inside an LTL formula one step forward in time. *)
val shift_ltl_forward_inputs : is_input:(Ast.ident -> bool) -> Ast.ltl -> Ast.ltl

(** Shift input references inside an LTL formula one step backward in time. *)
val shift_ltl_backward_inputs : is_input:(Ast.ident -> bool) -> Ast.ltl -> Ast.ltl
