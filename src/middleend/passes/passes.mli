(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

(** {1 Input Shifting} *)

(** Shift hexpr forward. *)
val shift_hexpr_forward :
  init_for_var:(Ast.ident -> Ast.iexpr) ->
  is_input:(Ast.ident -> bool) ->
  Ast.hexpr -> Ast.hexpr
(** Shift input hexprs forward by one step for next-state reasoning. *)
val shift_fo_forward_inputs :
  init_for_var:(Ast.ident -> Ast.iexpr) ->
  is_input:(Ast.ident -> bool) ->
  Ast.fo -> Ast.fo
(** Shift input references inside a FO formula forward by one step. *)
val shift_ltl_forward_inputs :
  init_for_var:(Ast.ident -> Ast.iexpr) ->
  is_input:(Ast.ident -> bool) ->
  Ast.ltl -> Ast.ltl
(** Shift input references inside an LTL formula forward by one step. *)

(** {1 Lemma Synthesis} *)
val conj_fo : Ast.fo list -> Ast.fo option
(** Conjoin a list of FO formulas, or None for empty. *)
val add_post_for_next_pre : Ast.user_node -> Ast.internal_node
(** Add lemma post-conditions that imply successor requires. *)
val add_post_for_next_pre_program :
  Ast.user_program -> Ast.internal_program
(** Apply add_post_for_next_pre to every node in a program. *)
