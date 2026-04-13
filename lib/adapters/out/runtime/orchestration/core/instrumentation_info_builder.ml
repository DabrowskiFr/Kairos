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

(** Builder of instrumentation-stage metrics.

    This module computes graph and summary counters from IR nodes and product
    analyses to populate flow metadata used by outputs and evaluation tools. *)

open Core_syntax
open Automaton_types

(** Helper value. *)

let ( let* ) = Result.bind

(** Module [Info_helpers]. *)

module Info_helpers = Instrumentation_info_helpers

(** [instrumentation_info_of_node] helper value. *)

let instrumentation_info_of_node ~(analyses : (ident * Temporal_automata.node_data) list)
    (node : Ir.node_ir) : (Flow_info.instrumentation_info, string) result =
  let* analysis = Info_helpers.analysis_of_node ~analyses node in
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
      Flow_info.warnings = [];
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

(** [instrumentation_info_of_ir] helper value. *)

let instrumentation_info_of_ir
    ~(automata : (Core_syntax.ident * automata_spec) list)
    ~(source_model : Verification_model.program_model) (program : Ir.program_ir)
    : (Flow_info.instrumentation_info, string) result =
  let source_nodes = Info_helpers.source_nodes_by_name source_model in
  let* analyses = Info_helpers.build_analyses ~automata ~source_nodes in
  let node_results =
    program.nodes |> List.map (instrumentation_info_of_node ~analyses)
  in
  node_results |> Result_utils.all
  |> Result.map
       (List.fold_left Info_helpers.merge_instrumentation_info
          Flow_info.empty_instrumentation_info)
