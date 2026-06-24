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

(** Application-level observability DTOs.

    These records are reported by use-cases and UI adapters. They are kept
    outside the port signatures so the dependency-inversion boundary does not
    also carry every diagnostic counter definition. *)

type why3_worker_counters = {
  worker_id : int;
  worker_input_goal_count : int;
  worker_prover_goal_count : int;
  worker_duplicate_goal_count : int;
  worker_fallback_count : int;
  worker_wall_s : float;
  worker_prepare_s : float;
  worker_print_s : float;
  worker_spawn_s : float;
  worker_wait_s : float;
  worker_solver_s : float;
  worker_last_goal : string;
}

type ir_size_metrics = {
  node_count : int;
  summary_count : int;
  safe_case_count : int;
  unsafe_case_count : int;
  propagation_requires_count : int;
  requires_count : int;
  ensures_count : int;
  init_invariant_goal_count : int;
  formula_occurrence_count : int;
  unique_formula_count : int;
}

type ir_pass_counters = {
  pass_name : string;
  before : ir_size_metrics;
  after_ : ir_size_metrics;
}

type ir_fact_family_counters = {
  pass_name : string;
  family_name : string;
  candidate_count : int;
  inserted_count : int;
  unique_candidate_count : int;
  unique_inserted_count : int;
}

type why3_product_group_counters = {
  group_name : string;
  node_name : string;
  transition_id : string;
  step_class : string;
  source_state : string;
  emitted_as_group : bool;
  split_due_to_cost : bool;
  edge_count : int;
  distinct_pre_count : int;
  distinct_post_count : int;
  post_implication_count : int;
  pre_text_bytes : int;
  post_text_bytes : int;
  estimated_cost : int;
  factor_kind : string;
  factor_original_estimated_cost : int;
  factor_post_common_estimated_cost : int;
  factor_pre_common_estimated_cost : int;
  factor_pre_and_post_common_estimated_cost : int;
  max_cost : int;
}

type why3_product_individual_reason_counters = {
  node_name : string;
  reason : string;
  count : int;
}

type timing_counters = {
  frontend_parse_s : float;
  snapshot_build_s : float;
  contract_partition_s : float;
  automata_generation_s : float;
  spot_s : float;
  spot_calls : int;
  z3_s : float;
  z3_calls : int;
  product_s : float;
  canonical_s : float;
  pre_s : float;
  product_reachability_s : float;
  post_s : float;
  temporal_lower_s : float;
  instrumentation_info_s : float;
  output_artifact_s : float;
  output_proof_run_s : float;
  output_map_s : float;
  why_gen_s : float;
  vc_smt_s : float;
  why3_setup_s : float;
  why3_parse_s : float;
  why3_typecheck_s : float;
  why3_task_extract_s : float;
  why3_split_vc_s : float;
  why3_prepare_s : float;
  why3_print_s : float;
  why3_spawn_s : float;
  why3_wait_s : float;
  why3_solver_s : float;
  why3_input_goal_count : int;
  why3_goal_count : int;
  why3_duplicate_goal_count : int;
  why3_fallback_count : int;
  why3_smt_fingerprint_count : int;
  why3_unique_smt_fingerprint_count : int;
  why3_workers : why3_worker_counters list;
  ir_passes : ir_pass_counters list;
  ir_fact_families : ir_fact_family_counters list;
  why3_product_groups : why3_product_group_counters list;
  why3_product_individual_reasons :
    why3_product_individual_reason_counters list;
}
