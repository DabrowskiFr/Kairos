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

val shift_fo_forward_inputs : is_input:(Ast.ident -> bool) -> Ast.fo -> Ast.fo
(* Shift input references inside an FO formula one step forward in time. Parameters: - [is_input]:
   predicate to decide which identifiers are inputs. Effect: - [HNow(x)] where [x] is an input
   becomes [pre_k(x, 1)]. - [pre_k(x, k)] where [x] is an input becomes [pre_k(x, k+1)]. Non-inputs
   and non-history expressions are left unchanged. *)

val shift_fo_backward_inputs : is_input:(Ast.ident -> bool) -> Ast.fo -> Ast.fo
(* Shift input references inside an FO formula one step backward in time. Parameters: - [is_input]:
   predicate to decide which identifiers are inputs. Effect: - [pre_k(x, 1)] where [x] is an input
   becomes [HNow(x)]. - [pre_k(x, k)] where [x] is an input becomes [pre_k(x, k-1)]. Non-inputs and
   non-history expressions are left unchanged. *)

val shift_fo_forward_all : Ast.fo -> Ast.fo
(* Shift all references inside an FO formula one step forward in time:
   [now(x)] -> [pre_k(x,1)] and [pre_k(x,k)] -> [pre_k(x,k+1)]. *)

val shift_fo_backward_all : Ast.fo -> Ast.fo
(* Shift all references inside an FO formula one step backward in time:
   [pre_k(x,1)] -> [now(x)] and [pre_k(x,k)] -> [pre_k(x,k-1)] for [k>1]. *)

val shift_ltl_forward_inputs : is_input:(Ast.ident -> bool) -> Ast.ltl -> Ast.ltl
(* Shift input references inside an ltl formula one step forward in time. *)
