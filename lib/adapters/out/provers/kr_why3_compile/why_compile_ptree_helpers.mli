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

(** Structural Why3 Ptree helpers used by the backend. *)

val empty_spec : unit -> Why3.Ptree.spec
val import_module : string -> Why3.Ptree.decl

val term_and : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_and_list : Why3.Ptree.term list -> Why3.Ptree.term
val term_or_list : Why3.Ptree.term list -> Why3.Ptree.term
val seq_exprs : Why3.Ptree.expr list -> Why3.Ptree.expr

val binder_term : Why3.Ptree.binder -> Why3.Ptree.term option
val param_of_binder : Why3.Ptree.binder -> Why3.Ptree.param option

val binders_used_by :
  Why_compile_expr.used_inputs ->
  Why3.Ptree.binder list ->
  Why3.Ptree.binder list
