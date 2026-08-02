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
(** Helper value. *)

let ( let* ) = Result.bind

(** Module [Info_helpers]. *)

module Info_helpers = Instrumentation_info_helpers

(** [instrumentation_info_of_node] helper value. *)

let instrumentation_info_of_node ~(analyses : (ident * Temporal_automata.node_data) list)
    (node : Core_syntax.history_free Ir.node_ir) : (Kairos_engine.Flow_info.instrumentation_info, string) result =
  let* analysis = Info_helpers.analysis_of_node ~analyses node in
  let require_automata_state_count =
    analysis.assume_monitor.state_count
  in
  let require_automata_edge_count =
    List.length analysis.assume_monitor.transitions
  in
  let ensures_automata_state_count =
    analysis.guarantee_monitor.state_count
  in
  let ensures_automata_edge_count =
    List.length analysis.guarantee_monitor.transitions
  in
  let product_edge_count =
    Product_types.step_count analysis.exploration
  in
  let product_state_count =
    List.length (Product_types.states analysis.exploration)
  in
  let canonical_summary_count = List.length node.summaries in
  let canonical_product_case_count =
    Info_helpers.product_case_count node.summaries
  in
  Ok
    {
      Kairos_engine.Flow_info.warnings = [];
      require_automata_state_count;
      require_automata_edge_count;
      ensures_automata_state_count;
      ensures_automata_edge_count;
      product_edge_count;
      product_state_count;
      canonical_summary_count;
      canonical_product_case_count;
    }

(** [instrumentation_info_of_ir] helper value. *)

let instrumentation_info_of_ir
    ~(product_nodes : Orchestration.product_node list)
    (program : Ir.program_ir)
    : (Kairos_engine.Flow_info.instrumentation_info, string) result =
  let analyses =
    List.map
      (fun (node : Orchestration.product_node) ->
        (node.proof_case.model.node_name, node.analysis))
      product_nodes
  in
  let node_results =
    program.nodes |> List.map (instrumentation_info_of_node ~analyses)
  in
  node_results |> Result_utils.all
  |> Result.map
       (List.fold_left Info_helpers.merge_instrumentation_info
          Kairos_engine.Flow_info.empty_instrumentation_info)
