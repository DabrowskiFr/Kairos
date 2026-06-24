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

(** Binder conversion and unused-parameter handling for generated Why3 code. *)

module StringSet = Why_compile_ptree_names.StringSet

val binder_expr : Why3.Ptree.binder -> Why3.Ptree.expr
val binder_term : Why3.Ptree.binder -> Why3.Ptree.term option
val param_of_binder : Why3.Ptree.binder -> Why3.Ptree.param option

val mark_unused_binders :
  StringSet.t -> Why3.Ptree.binder list -> Why3.Ptree.binder list

val helper_binders_without_unused_warnings :
  Why3.Ptree.binder list -> Why3.Ptree.spec -> Why3.Ptree.expr -> Why3.Ptree.binder list

val helper_binders_without_unused_parameters :
  Why3.Ptree.binder list -> Why3.Ptree.spec -> Why3.Ptree.expr -> Why3.Ptree.binder list
