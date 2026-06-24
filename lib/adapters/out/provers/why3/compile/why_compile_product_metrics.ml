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

module Product_groups = Why_compile_product_groups
module Group_boundary = Why_compile_product_group_boundary
module Group_terms = Why_compile_product_group_terms
module Step_names = Why_product_step_names

type context = {
  node_name : Core_syntax.ident;
  max_cost : int;
}

let record_group ctx ~group_name ~emitted_as_group ~split_due_to_cost ~entries
    (grouped : Product_groups.grouped_terms) =
  match entries with
  | [] -> ()
  | (_first_i, (first_sc : Why_contracts.step_contract_info), _first_t) :: _ ->
      let profile = Group_terms.profile grouped in
      let factor_candidate_costs = profile.factor_candidate_costs in
      External_timing.record_why3_product_group
        {
          group_name;
          node_name = ctx.node_name;
          transition_id = first_sc.step.transition_id;
          step_class = Step_names.product_step_class_name first_sc.step.step_class;
          source_state = Step_names.product_source_label first_sc.step.product_src;
          emitted_as_group;
          split_due_to_cost;
          edge_count = List.length entries;
          distinct_pre_count = profile.distinct_pre_count;
          distinct_post_count = profile.distinct_post_count;
          post_implication_count = profile.post_implication_count;
          pre_text_bytes = profile.pre_text_bytes;
          post_text_bytes = profile.post_text_bytes;
          estimated_cost = profile.estimated_cost;
          factor_kind =
            Group_boundary.factor_kind_name profile.factor_kind;
          factor_original_estimated_cost =
            factor_candidate_costs.original_estimated_cost;
          factor_post_common_estimated_cost =
            factor_candidate_costs.post_common_estimated_cost;
          factor_pre_common_estimated_cost =
            factor_candidate_costs.pre_common_estimated_cost;
          factor_pre_and_post_common_estimated_cost =
            factor_candidate_costs.pre_and_post_common_estimated_cost;
          max_cost = ctx.max_cost;
        }

let record_individual ctx (plan : Product_groups.individual_plan) =
  match plan.split_metrics with
  | None -> ()
  | Some metrics ->
      record_group ctx
        ~group_name:
          (Step_names.product_step_helper_name ~index:plan.index
             plan.contract.step)
        ~emitted_as_group:false
        ~split_due_to_cost:metrics.split_due_to_cost
        ~entries:[ (plan.index, plan.contract, plan.transition) ]
        metrics.grouped_terms

let record_grouped ctx (plan : Product_groups.grouped_plan) =
  match plan.entries with
  | [] -> ()
  | (first_i, (first_sc : Why_contracts.step_contract_info), _first_t) :: _ ->
      record_group ctx
        ~group_name:
          (Step_names.product_step_group_helper_name ~index:first_i
             first_sc.step)
        ~emitted_as_group:true ~split_due_to_cost:plan.split_due_to_cost
        ~entries:plan.entries plan.grouped_terms

let record_individual_reason_counts ctx plan =
  let add reason counts =
    let rec loop acc = function
      | [] -> List.rev ((reason, 1) :: acc)
      | (known_reason, count) :: rest when known_reason = reason ->
          List.rev_append acc ((known_reason, count + 1) :: rest)
      | item :: rest -> loop (item :: acc) rest
    in
    loop [] counts
  in
  plan
  |> List.fold_left
       (fun acc -> function
         | Product_groups.Individual individual ->
             add
               (Product_groups.individual_reason_name
                  individual.individual_reason)
               acc
         | Product_groups.Grouped _ -> acc)
       []
  |> List.iter (fun (reason, count) ->
         External_timing.record_why3_product_individual_reason
           { node_name = ctx.node_name; reason; count })

let record_plan ctx plan =
  record_individual_reason_counts ctx plan;
  plan
  |> List.iter (function
       | Product_groups.Individual individual -> record_individual ctx individual
       | Product_groups.Grouped grouped -> record_grouped ctx grouped)
