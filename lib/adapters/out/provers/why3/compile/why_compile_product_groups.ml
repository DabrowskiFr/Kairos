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

module Group_cost = Why_compile_product_group_cost
module Group_partition = Why_compile_product_group_partition
module Group_policy = Why_compile_product_group_policy
module Group_terms = Why_compile_product_group_terms

type entry = Group_terms.entry

type grouped_terms = Group_terms.t

type individual_reason = Group_policy.individual_reason =
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

let individual_reason_name = Group_policy.individual_reason_name

let individual ?split_metrics ~individual_reason (index, contract, transition) =
  Individual { index; contract; transition; individual_reason; split_metrics }

let grouped_plan ~grouped_terms ~split_due_to_cost entries =
  Grouped { entries; split_due_to_cost; grouped_terms = grouped_terms entries }

let split_groupable_entries ~grouped_terms group_cost_context ~max_cost entries =
  let chunks = Group_cost.split_by_cost group_cost_context ~max_cost entries in
  let split_due_to_cost = List.length chunks > 1 in
  chunks
  |> List.concat_map (function
       | [] -> []
       | [ (i, sc, t) as entry ] ->
           [
             individual
               ~individual_reason:Split_singleton
               ~split_metrics:
                 { split_due_to_cost; grouped_terms = grouped_terms [ entry ] }
               (i, sc, t);
           ]
       | chunk -> [ grouped_plan ~grouped_terms ~split_due_to_cost chunk ])

let plan_kernel_helpers ~(env : Why_compile_expr.env) ~(pre_vars_name : string)
    ~(post_vars_name : string) ~(group_why3_product_steps : bool)
    ~(max_cost : int) ~(simplify_runtime_actions : bool)
    ~step_pre_terms_with_rec ~step_post_terms_with_rec step_contracts =
  let grouped_terms entries =
    Group_terms.build ~env ~pre_vars_name ~post_vars_name
      ~step_pre_terms_with_rec ~step_post_terms_with_rec entries
  in
  let group_cost_context : Group_cost.context =
    {
      env;
      pre_vars_name;
      post_vars_name;
      step_pre_terms_with_rec;
      step_post_terms_with_rec;
    }
  in
  let indexed_transitions =
    step_contracts
    |> List.mapi (fun i (sc : Why_contracts.step_contract_info) ->
           let t =
             Why_runtime_view.transition_of_product_step
               ~simplify_runtime_actions sc.step
           in
           (i, sc, t))
  in
  indexed_transitions
  |> Group_partition.partition
  |> List.concat_map (fun group ->
         let entries = Group_partition.entries group in
         match
           Group_policy.decide_group ~group_why3_product_steps entries
         with
         | Group_policy.Groupable ->
             split_groupable_entries ~grouped_terms group_cost_context
               ~max_cost entries
         | Group_policy.Individual Empty_group -> []
         | Group_policy.Individual individual_reason ->
             entries
             |> List.map (fun entry -> individual ~individual_reason entry))
