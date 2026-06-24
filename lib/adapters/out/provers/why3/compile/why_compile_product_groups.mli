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

(** Product-step helper planning and cost estimation.

    This module decides which product steps are emitted individually and which
    ones are bundled into grouped helpers. It does not emit Why3 declarations. *)

type entry = Why_compile_product_group_terms.entry

type grouped_terms = Why_compile_product_group_terms.t

type individual_reason = Why_compile_product_group_policy.individual_reason =
  | Grouping_disabled
  | Empty_group
  | Singleton_group
  | Non_safe_step
  | Has_local_cuts
  | Split_singleton

type group_metrics = {
  split_due_to_cost : bool;
  grouped_terms : grouped_terms;
}

type individual_plan = {
  index : int;
  contract : Why_contracts.step_contract_info;
  transition : Why_runtime_view.runtime_transition_view;
  individual_reason : individual_reason;
  split_metrics : group_metrics option;
}

type grouped_plan = {
  entries : entry list;
  split_due_to_cost : bool;
  grouped_terms : grouped_terms;
}

type helper_plan_item =
  | Individual of individual_plan
  | Grouped of grouped_plan

val individual_reason_name : individual_reason -> string

val plan_kernel_helpers :
  env:Why_compile_expr.env ->
  pre_vars_name:string ->
  post_vars_name:string ->
  group_why3_product_steps:bool ->
  max_cost:int ->
  simplify_runtime_actions:bool ->
  step_pre_terms_with_rec:(string -> Why_contracts.step_contract_info -> Why3.Ptree.term list) ->
  step_post_terms_with_rec:(string -> Why_contracts.step_contract_info -> Why3.Ptree.term list) ->
  Why_contracts.step_contract_info list ->
  helper_plan_item list
