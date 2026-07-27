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

let accumulate_case_counts (summaries : 'phase Ir.product_step_summary list) :
    int * int * int =
  List.fold_left
    (fun (safe_acc, bad_a_acc, bad_g_acc) (summary : 'phase Ir.product_step_summary) ->
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
