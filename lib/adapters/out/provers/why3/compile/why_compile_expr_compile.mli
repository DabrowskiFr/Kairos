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

(** Compilation of Kairos expressions and formulas to Why3 Ptree nodes. *)

val compile_expr :
  Why_compile_expr_env.env -> Core_syntax.expr -> Why3.Ptree.expr

val compile_term :
  Why_compile_expr_env.env -> Core_syntax.expr -> Why3.Ptree.term

val term_of_outputs :
  Why_compile_expr_env.env -> Core_syntax.vdecl list -> Why3.Ptree.term option

val compile_hexpr :
  ?old:bool ->
  ?prefer_link:bool ->
  ?in_post:bool ->
  Why_compile_expr_env.env ->
  Core_syntax.hexpr ->
  Why3.Ptree.term

val compile_local_fo_formula_term :
  ?prefer_link:bool ->
  ?in_post:bool ->
  Why_compile_expr_env.env ->
  Core_syntax.hexpr ->
  Why3.Ptree.term

val pre_k_source_expr :
  Why_compile_expr_env.env -> Core_syntax.ident -> Why3.Ptree.expr

val pre_k_source_term :
  Why_compile_expr_env.env -> Core_syntax.ident -> Why3.Ptree.term
