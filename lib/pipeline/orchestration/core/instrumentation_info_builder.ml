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
open Ast
open Pretty

let ( let* ) = Result.bind

module Info_helpers = Instrumentation_info_helpers

let lower_guard_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list) ~(context : string)
    (guard : Core_syntax.hexpr) : (Core_syntax.hexpr, string) result =
  match Pre_k_lowering.lower_fo_formula_temporal_bindings ~temporal_bindings guard with
  | Some lowered -> Ok lowered
  | None ->
      Error
        (Printf.sprintf
           "Unable to lower temporal guard (%s) in product analysis for node %s: %s"
           context node_name (string_of_fo guard))

let lower_transition_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list) ~(context : string)
    ((src, guard, dst) : Automaton_types.transition) :
    (Automaton_types.transition, string) result =
  let* guard = lower_guard_for_kernel ~node_name ~temporal_bindings ~context guard in
  Ok (src, guard, dst)

let lower_product_step_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (step : Product_types.product_step) : (Product_types.product_step, string) result =
  let* prog_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"program guard"
      step.prog_guard
  in
  let* assume_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"assume guard"
      step.assume_guard
  in
  let* guarantee_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"guarantee guard"
      step.guarantee_guard
  in
  let* assume_edge =
    lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"assume edge"
      step.assume_edge
  in
  let* guarantee_edge =
    lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"guarantee edge"
      step.guarantee_edge
  in
  Ok { step with prog_guard; assume_guard; guarantee_guard; assume_edge; guarantee_edge }

let lower_analysis_for_kernel ~(node : Ir.node_ir)
    ~(analysis : Temporal_automata.node_data) :
    (Temporal_automata.node_data, string) result =
  let temporal_bindings = Ir_formula.temporal_bindings_of_node node in
  let node_name = node.semantics.sem_nname in
  let* assume_grouped_edges =
    analysis.assume_grouped_edges
    |> List.map
         (lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"assume automaton")
    |> Result_utils.all
  in
  let* guarantee_grouped_edges =
    analysis.guarantee_grouped_edges
    |> List.map
         (lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"guarantee automaton")
    |> Result_utils.all
  in
  let* steps =
    analysis.exploration.steps
    |> List.map (lower_product_step_for_kernel ~node_name ~temporal_bindings)
    |> Result_utils.all
  in
  Ok
    {
      analysis with
      assume_grouped_edges;
      guarantee_grouped_edges;
      exploration = { analysis.exploration with steps };
    }


let instrumentation_info_of_node ~(source_node : Ast.node)
    ~(analyses : (ident * Temporal_automata.node_data) list) (node : Ir.node_ir) :
    (Stage_info.instrumentation_info, string) result =
  let* analysis = Info_helpers.analysis_of_node ~analyses node in
  let* analysis_for_kernel = lower_analysis_for_kernel ~node ~analysis in
  let require_automaton =
    Automata_graph_render.render_require_automaton ~node_name:node.semantics.sem_nname ~analysis
  in
  let ensures_automaton =
    Automata_graph_render.render_ensures_automaton ~node_name:node.semantics.sem_nname ~analysis
  in
  let product =
    Automata_graph_render.render_product ~node_name:node.semantics.sem_nname ~analysis
  in
  let kernel_output =
    Proof_kernel_pass.compile_node
      {
        Proof_kernel_pass.node_name = node.semantics.sem_nname;
        source_node;
        node;
        analysis = analysis_for_kernel;
      }
  in
  let kernel_ir = kernel_output.normalized_ir in
  let exported_summary = kernel_output.exported_summary in
  let require_automata_state_count = List.length analysis.assume_state_labels in
  let require_automata_edge_count = List.length analysis.assume_grouped_edges in
  let ensures_automata_state_count = List.length analysis.guarantee_state_labels in
  let ensures_automata_edge_count = List.length analysis.guarantee_grouped_edges in
  let product_edge_count_full = List.length analysis.exploration.steps in
  let product_edge_count_live =
    analysis.exploration.steps
    |> List.filter (Info_helpers.product_step_is_live_requested ~analysis)
    |> List.length
  in
  let product_state_count_full = List.length analysis.exploration.states in
  let product_state_count_live =
    analysis.exploration.states
    |> List.filter (Info_helpers.product_state_is_live ~analysis)
    |> List.length
  in
  let canonical_summary_count = List.length node.summaries in
  let canonical_case_safe_count, canonical_case_bad_assumption_count,
      canonical_case_bad_guarantee_count =
    Info_helpers.accumulate_case_counts node.summaries
  in
  Ok
    {
      Stage_info.kernel_ir_nodes = [ kernel_ir ];
      exported_node_summaries = [ exported_summary ];
      kernel_pipeline_lines = [];
      warnings = [];
      guarantee_automaton_lines = String.split_on_char '\n' ensures_automaton.labels;
      assume_automaton_lines = String.split_on_char '\n' require_automaton.labels;
      canonical_lines = [];
      guarantee_automaton_dot = ensures_automaton.dot;
      assume_automaton_dot = require_automaton.dot;
      product_dot = product.dot;
      canonical_dot = "";
      require_automata_state_count;
      require_automata_edge_count;
      ensures_automata_state_count;
      ensures_automata_edge_count;
      product_edge_count_full;
      product_edge_count_live;
      product_state_count_full;
      product_state_count_live;
      canonical_summary_count;
      canonical_case_safe_count;
      canonical_case_bad_assumption_count;
      canonical_case_bad_guarantee_count;
    }

let instrumentation_info_of_ir ~(automata : Automata_generation.node_builds)
    ~(source_program : Ast.program) (program : Ir.program_ir)
    : (Stage_info.instrumentation_info, string) result =
  let source_nodes = Info_helpers.source_nodes_by_name source_program in
  let* analyses = Info_helpers.build_analyses ~automata ~source_nodes in
  let node_results =
    program.nodes
    |> List.map (fun (node : Ir.node_ir) ->
           let* source_node =
             Info_helpers.source_node_of_name ~source_nodes ~node_name:node.semantics.sem_nname
           in
           instrumentation_info_of_node ~source_node ~analyses node)
  in
  node_results |> Result_utils.all
  |> Result.map (List.fold_left Info_helpers.merge_instrumentation_info Stage_info.empty_instrumentation_info)
