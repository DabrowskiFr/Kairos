(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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

open Core_syntax
include Why_runtime_view_types

module Abs = Ir
module Slicing = Why_runtime_view_slicing
module Actions = Why_runtime_view_actions

let port_of_vdecl (v : vdecl) : port_view =
  { port_name = v.vname; port_type = v.vty }

let transition_of_ir ?transition_id ?(simplify_runtime_actions = true)
    (t : Abs.transition) : runtime_transition_view =
  let action_blocks =
    Actions.action_blocks_of_transition ~simplify_runtime_actions t
  in
  {
    transition_id =
      Option.value
        ~default:(Printf.sprintf "%s__%s" t.src_state t.dst_state)
        transition_id;
    src_state = t.src_state;
    dst_state = t.dst_state;
    guard = t.guard_expr;
    requires = [];
    ensures = [];
    body = t.body_stmts;
    action_blocks;
  }

let transition_of_product_step ?(simplify_runtime_actions = true)
    (step : runtime_product_transition_view) : runtime_transition_view =
  transition_of_ir ~transition_id:step.transition_id ~simplify_runtime_actions
    {
      src_state = step.src_state;
      dst_state = step.dst_state;
      guard_expr = step.guard;
      body_stmts = step.body;
    }

let of_ir_node ?(simplify_runtime_actions = true)
    ?(slice_transition_bodies = true) (node : Ir.node_ir) : t =
  let sem = node.semantics in
  let runtime =
    {
      node_name = sem.sem_nname;
      type_decls = sem.sem_type_decls;
      function_decls = sem.sem_function_decls;
      inputs = List.map port_of_vdecl sem.sem_inputs;
      outputs = List.map port_of_vdecl sem.sem_outputs;
      locals = List.map port_of_vdecl sem.sem_locals;
      control_states = sem.sem_states;
      init_control_state = sem.sem_init_state;
      product_transitions = [];
      assumes = node.source_info.assumes;
      guarantees = node.source_info.guarantees;
      init_invariant_goals = node.init_invariant_goals;
    }
  in
  let step_contract_projection = Step_contract_projection.of_ir_node node in
  let runtime_step_class_of_projection = function
    | Step_contract_projection.StepSafe -> StepSafe
    | Step_contract_projection.StepBadGuarantee -> StepBadGuarantee
  in
  let body_for_contract (contract : Step_contract_projection.step_contract)
      formulas =
    if slice_transition_bodies then
      Slicing.slice_body_for_formulas contract.program_step.body_stmts formulas
    else contract.program_step.body_stmts
  in
  let runtime_product_transition_of_contract
      (contract : Step_contract_projection.step_contract) :
      runtime_product_transition_view * Ir.summary_formula =
    let ensures = Slicing.dedup_summary_formulas contract.ensures in
    let elaboration_checks =
      Slicing.dedup_summary_formulas contract.elaboration_checks
    in
    let body_formulas =
      match contract.step_class with
      | Step_contract_projection.StepSafe -> ensures @ elaboration_checks
      | Step_contract_projection.StepBadGuarantee -> contract.forbidden
    in
    ( {
        transition_id = contract.transition_id;
        src_state = contract.program_step.src_state;
        dst_state = contract.program_step.dst_state;
        guard = contract.program_step.guard_expr;
        body = body_for_contract contract body_formulas;
        step_class = runtime_step_class_of_projection contract.step_class;
        product_src = contract.product_src;
        product_dst = contract.product_dst;
        requires = contract.requires;
        local_requires = contract.runtime_requires;
        propagates = contract.propagates;
        ensures;
        elaboration_checks;
        forbidden = contract.forbidden;
      },
      contract.assume_guard )
  in
  let grouped_product_transition_entries =
    List.map runtime_product_transition_of_contract
      step_contract_projection.step_contracts
  in
  let group_key (t : runtime_product_transition_view) =
    ( t.step_class,
      t.transition_id,
      t.src_state,
      t.dst_state,
      t.guard,
      t.body,
      t.product_src,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.requires,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.local_requires,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.ensures,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.elaboration_checks,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.forbidden )
  in
  let product_transition_groups = Hashtbl.create 256 in
  let product_transition_order = ref [] in
  grouped_product_transition_entries
  |> List.iter (fun (transition, assume_guard) ->
         let key = group_key transition in
         if not (Hashtbl.mem product_transition_groups key) then
           product_transition_order := key :: !product_transition_order;
         let representative, assume_guards =
           Hashtbl.find_opt product_transition_groups key
           |> Option.value ~default:(transition, [])
         in
         Hashtbl.replace product_transition_groups key
           (representative, assume_guards @ [ assume_guard ]));
  let product_transitions =
    List.rev !product_transition_order
    |> List.filter_map (fun key ->
           let representative, assume_guards =
             Hashtbl.find product_transition_groups key
           in
           match Slicing.disj_summary_formulas assume_guards with
           | None -> None
           | Some assume_guard ->
               Some
                 {
                   representative with
                   requires = representative.requires @ [ assume_guard ];
                 })
  in
  { runtime with product_transitions }
