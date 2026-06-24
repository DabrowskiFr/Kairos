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
module Group_terms = Why_compile_product_group_terms

type entry = Group_terms.entry

type grouped_terms = Group_terms.t = {
  pre_term : Why3.Ptree.term;
  post_body : Why3.Ptree.term;
  distinct_pre_count : int;
  distinct_post_count : int;
  post_implication_count : int;
  pre_text_bytes : int;
  post_text_bytes : int;
  estimated_cost : int;
}

type group_metrics = {
  split_due_to_cost : bool;
  grouped_terms : grouped_terms;
}

type individual_plan = {
  index : int;
  contract : Why_contracts.step_contract_info;
  transition : Why_runtime_view.runtime_transition_view;
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

let individual ?split_metrics (index, contract, transition) =
  Individual { index; contract; transition; split_metrics }

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
  let groups = Hashtbl.create 128 in
  let order = ref [] in
  let group_key (_i, (sc : Why_contracts.step_contract_info), t) =
    (sc.step.step_class, t)
  in
  List.iter
    (fun entry ->
      let key = group_key entry in
      if not (Hashtbl.mem groups key) then order := key :: !order;
      let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
      Hashtbl.replace groups key (entry :: previous))
    indexed_transitions;
  List.rev !order
  |> List.concat_map (fun key ->
         let entries = Hashtbl.find groups key |> List.rev in
         let group_is_safe =
           match entries with
           | [] -> false
           | (_i, (sc : Why_contracts.step_contract_info), _t) :: _ ->
               sc.step.step_class = Why_runtime_view.StepSafe
         in
         let groupable =
           group_why3_product_steps
           && List.length entries > 1
           && group_is_safe
           && List.for_all
                (fun (_i, (sc : Why_contracts.step_contract_info), _t) ->
                  sc.local_cuts = [])
                entries
         in
         if groupable then
           let chunks =
             Group_cost.split_by_cost group_cost_context ~max_cost entries
           in
           let split_due_to_cost = List.length chunks > 1 in
           chunks
           |> List.concat_map (function
                | [] -> []
                | [ (i, sc, t) as entry ] ->
                    [
                      individual
                        ~split_metrics:
                          {
                            split_due_to_cost;
                            grouped_terms = grouped_terms [ entry ];
                          }
                        (i, sc, t);
                    ]
                | chunk ->
                    [
                      Grouped
                        {
                          entries = chunk;
                          split_due_to_cost;
                          grouped_terms = grouped_terms chunk;
                        };
                    ])
         else
           entries
           |> List.map (fun entry -> individual entry))
