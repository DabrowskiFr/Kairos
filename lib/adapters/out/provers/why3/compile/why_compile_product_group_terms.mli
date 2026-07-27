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

(** Canonical construction of symbolic terms for grouped product-step helpers. *)

val pre_vars_name : string
val post_vars_name : string

type entry = int * Step_contract_projection.step_contract

type t = {
  pre_term : Why3.Ptree.term;
  pre_inputs : Why_compile_expr.used_inputs;
  post_body : Why3.Ptree.term;
  post_inputs : Why_compile_expr.used_inputs;
}

val build :
  env:Why_compile_expr.env ->
  step_pre_terms_with_rec:
    (Why_compile_expr.env ->
    string ->
    Step_contract_projection.step_contract ->
    Why3.Ptree.term list) ->
  step_post_terms_with_rec:
    (Why_compile_expr.env ->
    string ->
    Step_contract_projection.step_contract ->
    Why3.Ptree.term list) ->
  entry list ->
  t
