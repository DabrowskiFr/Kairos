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

(** {1 Statement Compilation} *)

(** Compile seq. *)
val compile_seq :
  Support.env ->
  (Ast.ident * Ast.iexpr list * Ast.ident list ->
   (Why3.Ptree.ident * Why3.Ptree.expr) list * Why3.Ptree.term list) ->
  Ast.stmt list -> Why3.Ptree.expr

(** {1 Transition Compilation} *)

(** Compile state branch. *)
val compile_state_branch :
  Support.env ->
  (Ast.ident * Ast.iexpr list * Ast.ident list ->
   (Why3.Ptree.ident * Why3.Ptree.expr) list * Why3.Ptree.term list) ->
  Ast.ident -> Ast.transition list -> Why3.Ptree.reg_branch
(** Compile transitions. *)
val compile_transitions :
  Support.env ->
  (Ast.ident * Ast.iexpr list * Ast.ident list ->
   (Why3.Ptree.ident * Why3.Ptree.expr) list * Why3.Ptree.term list) ->
  Ast.transition list -> Why3.Ptree.expr
