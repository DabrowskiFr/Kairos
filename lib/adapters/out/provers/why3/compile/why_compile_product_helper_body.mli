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

(** Why3 bodies and function expressions for product-step helpers. *)

val helper_function :
  Why3.Ptree.binder list ->
  Why3.Ptree.spec ->
  Why3.Ptree.expr ->
  Why3.Ptree.expr

val individual_body :
  env:Why_compile_expr.env ->
  Why_runtime_view.runtime_transition_view ->
  local_cuts:Why3.Ptree.term list ->
  Why3.Ptree.expr

val grouped_body :
  env:Why_compile_expr.env ->
  Why_runtime_view.runtime_transition_view ->
  post_call:(pre_snapshot_name:string -> Why3.Ptree.term) ->
  Why3.Ptree.expr
