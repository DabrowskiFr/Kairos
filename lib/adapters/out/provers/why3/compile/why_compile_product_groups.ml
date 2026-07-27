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

(** Canonical planning policy for individual and grouped product-step helpers. *)

module Group_partition = struct
  type entry = Why_compile_product_group_terms.entry

  let group_key (_i, (sc : Step_contract_projection.step_contract)) =
    (sc.step_class, sc.transition_id, sc.program_step)

  let partition entries =
    let groups = Hashtbl.create 128 in
    let order = ref [] in
    List.iter
      (fun entry ->
        let key = group_key entry in
        if not (Hashtbl.mem groups key) then order := key :: !order;
        let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
        Hashtbl.replace groups key (entry :: previous))
      entries;
    List.rev !order
    |> List.map (fun key -> Hashtbl.find groups key |> List.rev)
end

module Group_policy = struct
  type entry = Why_compile_product_group_terms.entry

  type decision = Groupable | Individual

  let group_is_safe = function
    | [] -> false
    | (_i, (sc : Step_contract_projection.step_contract)) :: _ ->
        sc.step_class = Step_contract_projection.StepSafe

  let decide_group ~(group_why3_product_steps : bool) entries =
    if not group_why3_product_steps then Individual
    else
      match entries with
      | [] | [ _ ] -> Individual
      | _ when not (group_is_safe entries) -> Individual
      | _ -> Groupable
end

module Group_terms = Why_compile_product_group_terms

type individual_plan = {
  index : int;
  contract : Step_contract_projection.step_contract;
}

type grouped_plan = {
  index : int;
  contract : Step_contract_projection.step_contract;
  formulas : Core_syntax.history_free Ir.summary_formula list;
  grouped_terms : Group_terms.t;
}

type helper_plan_item =
  | Individual of individual_plan
  | Grouped of grouped_plan

let build ~(env : Why_compile_expr.env) ~formula_sharing
    ~(group_why3_product_steps : bool) step_contracts =
  let formulas entries =
    entries
    |> List.concat_map
         (fun (_index, contract) ->
           Step_contract_projection.preconditions contract
           @ Step_contract_projection.postconditions contract
           @ Step_contract_projection.exclusions contract)
  in
  let grouped_terms entries =
    Group_terms.build ~env
      ~step_pre_terms_with_rec:
        (Why_compile_product_specs.step_pre_terms_with_rec formula_sharing)
      ~step_post_terms_with_rec:
        (Why_compile_product_specs.step_post_terms_with_rec formula_sharing)
      entries
  in
  let indexed_transitions =
    step_contracts
    |> List.mapi (fun i (sc : Step_contract_projection.step_contract) -> (i, sc))
  in
  indexed_transitions
  |> Group_partition.partition
  |> List.concat_map (fun entries ->
         match
           Group_policy.decide_group ~group_why3_product_steps entries
         with
         | Group_policy.Groupable ->
             let index, contract = List.hd entries in
             [
               Grouped
                 {
                   index;
                   contract;
                   formulas = formulas entries;
                   grouped_terms = grouped_terms entries;
                 };
             ]
         | Group_policy.Individual ->
             List.map
               (fun (index, contract) -> Individual { index; contract })
               entries)
