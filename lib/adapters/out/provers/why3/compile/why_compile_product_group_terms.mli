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

(** Construction of symbolic terms for grouped product-step helpers. *)

type entry =
  int * Why_contracts.step_contract_info * Why_runtime_view.runtime_transition_view

type t = {
  pre_term : Why3.Ptree.term;
  post_body : Why3.Ptree.term;
  distinct_pre_count : int;
  distinct_post_count : int;
  post_implication_count : int;
  pre_text_bytes : int;
  post_text_bytes : int;
  estimated_cost : int;
}

val build :
  env:Why_compile_expr.env ->
  pre_vars_name:string ->
  post_vars_name:string ->
  step_pre_terms_with_rec:
    (string -> Why_contracts.step_contract_info -> Why3.Ptree.term list) ->
  step_post_terms_with_rec:
    (string -> Why_contracts.step_contract_info -> Why3.Ptree.term list) ->
  entry list ->
  t
