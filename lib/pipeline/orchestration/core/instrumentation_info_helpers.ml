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

let ( let* ) = Result.bind

let program_transitions_of_ast_node (node : Ast.node) : Ir.transition list =
  Ir_transition.prioritized_program_transitions_of_node node

let source_nodes_by_name (source_program : Ast.program) : (ident * node) list =
  List.map (fun (node : Ast.node) -> (node.semantics.sem_nname, node)) source_program

let source_node_of_name ~(source_nodes : (ident * Ast.node) list) ~(node_name : ident) :
    (Ast.node, string) result =
  Result_utils.find_assoc
    ~missing:(fun name -> Printf.sprintf "Missing source AST node for IR node %s" name)
    node_name source_nodes

let analysis_context_of_source_node (source_node : Ast.node) : Ir.node_ir =
  let semantics = Ast.semantics_of_node source_node in
  {
    Ir.semantics =
      {
        sem_nname = semantics.sem_nname;
        sem_inputs = semantics.sem_inputs;
        sem_outputs = semantics.sem_outputs;
        sem_locals = semantics.sem_locals;
        sem_states = semantics.sem_states;
        sem_init_state = semantics.sem_init_state;
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout = Pre_k_layout.build_pre_k_infos source_node;
    summaries = [];
    init_invariant_goals = [];
  }

let build_node_analysis ~(automata : Automata_generation.node_builds)
    ~(program_transitions : Ir.transition list) (source_node : Ast.node) :
    (Temporal_automata.node_data, string) result =
  let node = analysis_context_of_source_node source_node in
  let* build =
    Result_utils.find_assoc
      ~missing:(fun node_name -> Printf.sprintf "Missing automata build for IR node %s" node_name)
      node.semantics.sem_nname automata
  in
  Ok (Product_build.analyze_node ~build ~node ~program_transitions)

let build_analyses ~(automata : Automata_generation.node_builds)
    ~(source_nodes : (ident * Ast.node) list) :
    ((ident * Temporal_automata.node_data) list, string) result =
  source_nodes
  |> List.map (fun (node_name, source_node) ->
         let analysis =
           build_node_analysis ~automata
             ~program_transitions:(program_transitions_of_ast_node source_node)
             source_node
         in
         Result.map (fun value -> (node_name, value)) analysis)
  |> Result_utils.all

let analysis_of_node ~(analyses : (ident * Temporal_automata.node_data) list) (node : Ir.node_ir) :
    (Temporal_automata.node_data, string) result =
  Result_utils.find_assoc
    ~missing:(fun node_name -> Printf.sprintf "Missing product analysis for IR node %s" node_name)
    node.semantics.sem_nname analyses

let product_state_is_live ~(analysis : Temporal_automata.node_data) (st : Product_types.product_state) :
    bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let product_step_is_live_requested ~(analysis : Temporal_automata.node_data)
    (step : Product_types.product_step) : bool =
  let src_not_g_bad =
    analysis.guarantee_bad_idx < 0 || step.src.guarantee_state <> analysis.guarantee_bad_idx
  in
  let dst_not_a_bad =
    analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx
  in
  src_not_g_bad && dst_not_a_bad

let accumulate_case_counts (summaries : Ir.product_step_summary list) :
    int * int * int =
  List.fold_left
    (fun (safe_acc, bad_a_acc, bad_g_acc) (summary : Ir.product_step_summary) ->
      (safe_acc + List.length summary.safe_cases, bad_a_acc,
       bad_g_acc + List.length summary.unsafe_cases))
    (0, 0, 0)
    summaries

let merge_instrumentation_info (left : Stage_info.instrumentation_info)
    (right : Stage_info.instrumentation_info) : Stage_info.instrumentation_info =
  {
    Stage_info.warnings = left.warnings @ right.warnings;
    require_automata_state_count =
      left.require_automata_state_count + right.require_automata_state_count;
    require_automata_edge_count =
      left.require_automata_edge_count + right.require_automata_edge_count;
    ensures_automata_state_count =
      left.ensures_automata_state_count + right.ensures_automata_state_count;
    ensures_automata_edge_count =
      left.ensures_automata_edge_count + right.ensures_automata_edge_count;
    product_edge_count_full = left.product_edge_count_full + right.product_edge_count_full;
    product_edge_count_live = left.product_edge_count_live + right.product_edge_count_live;
    product_state_count_full = left.product_state_count_full + right.product_state_count_full;
    product_state_count_live = left.product_state_count_live + right.product_state_count_live;
    canonical_summary_count = left.canonical_summary_count + right.canonical_summary_count;
    canonical_case_safe_count =
      left.canonical_case_safe_count + right.canonical_case_safe_count;
    canonical_case_bad_assumption_count =
      left.canonical_case_bad_assumption_count + right.canonical_case_bad_assumption_count;
    canonical_case_bad_guarantee_count =
      left.canonical_case_bad_guarantee_count + right.canonical_case_bad_guarantee_count;
  }
