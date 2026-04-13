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

(** Helpers shared by instrumentation metrics computation.

    This module provides lookups, product liveness predicates and aggregation
    helpers used by {!Instrumentation_info_builder}. *)

open Core_syntax
open Automaton_types

(** Helper value. *)

let ( let* ) = Result.bind

(** [program_transitions_of_ast_node] helper value. *)

let program_transitions_of_model_node (node : Verification_model.node_model) :
    Verification_model.program_step list =
  node.steps

(** [source_nodes_by_name] helper value. *)

let source_nodes_by_name (source_program : Verification_model.program_model) :
    (ident * Verification_model.node_model) list =
  List.map (fun (node : Verification_model.node_model) -> (node.node_name, node)) source_program

(** [analysis_context_of_source_node] helper value. *)

let analysis_context_of_source_node (source_node : Verification_model.node_model) : Ir.node_ir =
  {
    Ir.semantics =
      {
        sem_nname = source_node.node_name;
        sem_inputs = source_node.inputs;
        sem_outputs = source_node.outputs;
        sem_locals = source_node.locals;
        sem_states = source_node.states;
        sem_init_state = source_node.init_state;
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout = Pre_k_layout.build_pre_k_infos source_node;
    summaries = [];
    init_invariant_goals = [];
  }

(** [build_node_analysis] helper value. *)

let build_node_analysis
    ~(automata : (Core_syntax.ident * automata_spec) list)
    (source_node : Verification_model.node_model) :
    (Temporal_automata.node_data, string) result =
  let node = analysis_context_of_source_node source_node in
  let* build =
    Result_utils.find_assoc
      ~missing:(fun node_name -> Printf.sprintf "Missing automata build for IR node %s" node_name)
      node.semantics.sem_nname automata
  in
  Ok
    (Product_build.analyze_node ~build ~node:source_node
       ~program_transitions:(program_transitions_of_model_node source_node))

(** [build_analyses] helper value. *)

let build_analyses
    ~(automata : (Core_syntax.ident * automata_spec) list)
    ~(source_nodes : (ident * Verification_model.node_model) list) :
    ((ident * Temporal_automata.node_data) list, string) result =
  source_nodes
  |> List.map (fun (node_name, source_node) ->
         let analysis = build_node_analysis ~automata source_node in
         Result.map (fun value -> (node_name, value)) analysis)
  |> Result_utils.all

(** [analysis_of_node] helper value. *)

let analysis_of_node ~(analyses : (ident * Temporal_automata.node_data) list) (node : Ir.node_ir) :
    (Temporal_automata.node_data, string) result =
  Result_utils.find_assoc
    ~missing:(fun node_name -> Printf.sprintf "Missing product analysis for IR node %s" node_name)
    node.semantics.sem_nname analyses

(** [product_state_is_live] helper value. *)

let product_state_is_live ~(analysis : Temporal_automata.node_data) (st : Product_types.product_state) :
    bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

(** [product_step_is_live_requested] helper value. *)

let product_step_is_live_requested ~(analysis : Temporal_automata.node_data)
    (step : Product_types.product_step) : bool =
  let src_not_g_bad =
    analysis.guarantee_bad_idx < 0 || step.src.guarantee_state <> analysis.guarantee_bad_idx
  in
  let dst_not_a_bad =
    analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx
  in
  src_not_g_bad && dst_not_a_bad

(** [accumulate_case_counts] helper value. *)

let accumulate_case_counts (summaries : Ir.product_step_summary list) :
    int * int * int =
  List.fold_left
    (fun (safe_acc, bad_a_acc, bad_g_acc) (summary : Ir.product_step_summary) ->
      (safe_acc + List.length summary.safe_cases, bad_a_acc,
       bad_g_acc + List.length summary.unsafe_cases))
    (0, 0, 0)
    summaries

(** [merge_instrumentation_info] helper value. *)

let merge_instrumentation_info (left : Flow_info.instrumentation_info)
    (right : Flow_info.instrumentation_info) : Flow_info.instrumentation_info =
  {
    Flow_info.warnings = left.warnings @ right.warnings;
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
