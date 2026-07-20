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
open Pre_k_layout

module Abs = Ir
module PT = Product_types

type node_input = {
  node_name : ident;
  source_node : Verification_model.node_model;
  node : Ir.node_ir;
  analysis : Temporal_automata.node_data;
}

type node_output = {
  normalized_ir : Proof_kernel_types.node_ir;
  exported_summary : Proof_kernel_types.exported_node_summary_ir;
}

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let fo_of_expr (e : expr) : Core_syntax.hexpr =
  Core_syntax_builders.hexpr_of_expr e

let extract_delay_spec (guarantees : ltl list) : (ident * ident) option =
  let rec find_in_ltl = function
    | LG a -> find_in_ltl a
    | LX a -> find_in_ltl a
    | LAtom (lhs, REq, rhs) -> (
        match (lhs.hexpr, rhs.hexpr) with
        | HVar out, HPreK (b, 1) -> Some (out, b)
        | HPreK (b, 1), HVar out -> Some (out, b)
        | _ -> None)
    | _ -> None
  in
  List.find_map find_in_ltl guarantees

let program_transitions_of_model_node (node : Verification_model.node_model) : Ir.transition list =
  Ir_transition.prioritized_program_transitions_of_node node

let automaton_guard_fo (g : Automaton_types.guard) : Core_syntax.hexpr =
  simplify_fo g

let product_state_of_pt (st : PT.product_state) : Proof_kernel_types.product_state_ir =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state;
    guarantee_state_index = st.guarantee_state;
  }

let is_live_state ~(analysis : Temporal_automata.node_data) (st : PT.product_state) : bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let temporal_locals_of_layout ~(existing_locals : vdecl list) (layout : Ir.temporal_layout) :
    vdecl list =
  let existing = List.map (fun (v : vdecl) -> v.vname) existing_locals in
  layout
  |> List.fold_left
       (fun acc info ->
	         if List.exists
	              (fun (existing_info : Pre_k_layout.pre_k_info) ->
	                existing_info.Pre_k_layout.var_name = info.Pre_k_layout.var_name
	                && existing_info.Pre_k_layout.names = info.Pre_k_layout.names)
	              acc
         then acc
         else acc @ [ info ])
       []
  |> List.concat_map (fun info ->
         List.filter_map
           (fun name ->
             if List.mem name existing then None else Some { vname = name; vty = info.vty })
           info.names)

let build_reactive_program ~(node_name : ident) ~(source_node : Verification_model.node_model) :
    Proof_kernel_types.reactive_program_ir =
  Proof_kernel_product.build_reactive_program ~node_name
    ~source_node
    ~program_transitions:(program_transitions_of_model_node source_node)

let build_automaton ~(role : Proof_kernel_types.automaton_role) ~(labels : string list) ~(bad_idx : int)
    ~(grouped_edges : PT.automaton_edge list) :
    Proof_kernel_types.safety_automaton_ir =
  Proof_kernel_product.build_automaton ~role ~labels ~bad_idx ~grouped_edges
    ~automaton_guard_fo

let build_product_step ~(reactive_program : Proof_kernel_types.reactive_program_ir) (step : PT.product_step) :
    Proof_kernel_types.product_step_ir =
  Proof_kernel_product.build_product_step ~reactive_program step

let is_feasible_product_step ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    (step : Proof_kernel_types.product_step_ir) : bool =
  Proof_kernel_product.is_feasible_product_step ~node ~analysis step

let build_generated_clauses ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    ~(initial_state : Proof_kernel_types.product_state_ir) ~(steps : Proof_kernel_types.product_step_ir list) :
    Proof_kernel_types.generated_clause_ir list =
  Proof_kernel_generated_clauses.build_generated_clauses ~node ~analysis ~initial_state ~steps
    ~automaton_guard_fo
    ~is_live_state

let node_signature_of_model ~(temporal_layout : Ir.temporal_layout) (n : Verification_model.node_model) :
    Proof_kernel_types.node_signature_ir =
  let source_locals = n.locals @ n.ghosts in
  let temporal_locals = temporal_locals_of_layout ~existing_locals:source_locals temporal_layout in
  {
    node_name = n.node_name;
    inputs = n.inputs;
    outputs = n.outputs;
    locals = source_locals @ temporal_locals;
    states = n.states;
    init_state = n.init_state;
  }

let build_exported_summary ~(input : node_input)
    ~(normalized_ir : Proof_kernel_types.node_ir) :
    Proof_kernel_types.exported_node_summary_ir =
  let source_node = input.source_node in
  let node = input.node in
  {
    signature = node_signature_of_model ~temporal_layout:node.temporal_layout source_node;
    normalized_ir;
    coherency_goals = node.init_invariant_goals;
    temporal_layout = node.temporal_layout;
    delay_spec = extract_delay_spec node.source_info.guarantees;
    assumes = node.source_info.assumes;
    guarantees = node.source_info.guarantees;
  }

let build_normalized_ir (input : node_input) : Proof_kernel_types.node_ir =
  let node_name = input.node_name in
  let source_node = input.source_node in
  let node = input.node in
  let analysis = input.analysis in
  let reactive_program = build_reactive_program ~node_name ~source_node in
  let assume_automaton =
    build_automaton ~role:Proof_kernel_types.Assume ~labels:analysis.assume_state_labels
      ~bad_idx:analysis.assume_bad_idx ~grouped_edges:analysis.assume_grouped_edges
  in
  let guarantee_automaton =
    build_automaton ~role:Proof_kernel_types.Guarantee ~labels:analysis.guarantee_state_labels
      ~bad_idx:analysis.guarantee_bad_idx ~grouped_edges:analysis.guarantee_grouped_edges
  in
  let initial_product_state = product_state_of_pt analysis.exploration.initial_state in
  let live_product_states =
    analysis.exploration.states |> List.filter (is_live_state ~analysis) |> List.sort_uniq PT.compare_state
  in
  let product_states = List.map product_state_of_pt live_product_states in
  let explicit_steps =
    List.map (build_product_step ~reactive_program) analysis.exploration.steps
    |> List.filter (is_feasible_product_step ~node ~analysis)
  in
  let product_steps = explicit_steps in
  let product_coverage =
    if explicit_steps <> [] then Proof_kernel_types.CoverageExplicit
    else Proof_kernel_types.CoverageEmpty
  in
  let historical_generated_clauses =
    build_generated_clauses ~node ~analysis ~initial_state:initial_product_state ~steps:product_steps
  in
  let eliminated_generated_clauses =
    List.filter_map Proof_kernel_clause_lowering.lower_generated_clause
      historical_generated_clauses
  in
  let symbolic_generated_clauses =
    List.concat_map Proof_kernel_clause_lowering.relationalize_generated_clause
      eliminated_generated_clauses
  in
  let proof_step_summaries =
    Proof_kernel_step_summaries.build_proof_step_summaries ~node ~reactive_program ~product_steps
      ~initial_product_state ~symbolic_generated_clauses
  in
  let ghost_locals =
    temporal_locals_of_layout ~existing_locals:(source_node.locals @ source_node.ghosts) node.temporal_layout
  in
  {
    Proof_kernel_types.reactive_program;
    assume_automaton;
    guarantee_automaton;
    initial_product_state;
    product_states;
    product_steps;
    product_coverage;
    temporal_layout = node.temporal_layout;
    historical_generated_clauses;
    eliminated_generated_clauses;
    symbolic_generated_clauses;
    proof_step_summaries;
    ghost_locals;
  }

let compile_node (input : node_input) : node_output =
  let normalized_ir = build_normalized_ir input in
  let exported_summary = build_exported_summary ~input ~normalized_ir in
  { normalized_ir; exported_summary }
