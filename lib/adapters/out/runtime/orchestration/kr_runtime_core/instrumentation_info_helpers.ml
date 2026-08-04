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
(** [analysis_of_node] helper value. *)

let analysis_of_node ~(analyses : (ident * Temporal_automata.node_data) list) (node : 'phase Ir.node_ir) :
    (Temporal_automata.node_data, string) result =
  Result_utils.find_assoc
    ~missing:(fun node_name -> Printf.sprintf "Missing product analysis for IR node %s" node_name)
    node.semantics.sem_nname analyses

(** [accumulate_case_counts] helper value. *)

let product_case_count
    (summaries : 'phase Ir.product_step_summary list) : int =
  List.fold_left
    (fun count (summary : 'phase Ir.product_step_summary) ->
      count + List.length summary.product_cases)
    0
    summaries

(** [merge_instrumentation_info] helper value. *)

let merge_instrumentation_info (left : Kr_engine.Flow_info.instrumentation_info)
    (right : Kr_engine.Flow_info.instrumentation_info) : Kr_engine.Flow_info.instrumentation_info =
  {
    Kr_engine.Flow_info.warnings = left.warnings @ right.warnings;
    require_automata_state_count =
      left.require_automata_state_count + right.require_automata_state_count;
    require_automata_edge_count =
      left.require_automata_edge_count + right.require_automata_edge_count;
    ensures_automata_state_count =
      left.ensures_automata_state_count + right.ensures_automata_state_count;
    ensures_automata_edge_count =
      left.ensures_automata_edge_count + right.ensures_automata_edge_count;
    product_edge_count =
      left.product_edge_count + right.product_edge_count;
    product_state_count =
      left.product_state_count + right.product_state_count;
    canonical_summary_count = left.canonical_summary_count + right.canonical_summary_count;
    canonical_product_case_count =
      left.canonical_product_case_count
      + right.canonical_product_case_count;
  }
