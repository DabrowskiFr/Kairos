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

(* {1 Statement Compilation} *)

(* Compile a sequence of statements to a Why3 expression. *)
val compile_seq :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  (Why3.Ptree.ident * Why3.Ptree.expr) list * Why3.Ptree.term list * Why3.Ptree.expr list) ->
  Why_runtime_view.runtime_action_view list ->
  Why3.Ptree.expr

(* {1 Transition Compilation} *)

(* Compile a state branch (pattern match arm) for transitions. *)
val compile_state_branch :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  (Why3.Ptree.ident * Why3.Ptree.expr) list * Why3.Ptree.term list * Why3.Ptree.expr list) ->
  Ast.ident ->
  Why_runtime_view.runtime_transition_view list ->
  Why3.Ptree.reg_branch

(* Compile all transitions into a Why3 expression. *)
val compile_transitions :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  (Why3.Ptree.ident * Why3.Ptree.expr) list * Why3.Ptree.term list * Why3.Ptree.expr list) ->
  Why_runtime_view.state_branch_view list ->
  Why3.Ptree.expr

(* Compile a full runtime view into the body of `step`. *)
val compile_runtime_view :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  (Why3.Ptree.ident * Why3.Ptree.expr) list * Why3.Ptree.term list * Why3.Ptree.expr list) ->
  Why_runtime_view.t ->
  Why3.Ptree.expr
