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

(** Process-local timing counters for external backends. *)

type why3_worker_snapshot = {
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

type ir_pass_snapshot = {
  pass_name : string;
  before : ir_size_metrics;
  after_ : ir_size_metrics;
}

type ir_fact_family_snapshot = {
  pass_name : string;
  family_name : string;
  candidate_count : int;
  inserted_count : int;
  unique_candidate_count : int;
  unique_inserted_count : int;
}

type why3_product_group_snapshot = {
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

type why3_product_individual_reason_snapshot = {
  node_name : string;
  reason : string;
  count : int;
}

type snapshot = {
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
  why3_workers : why3_worker_snapshot list;
  ir_passes : ir_pass_snapshot list;
  ir_fact_families : ir_fact_family_snapshot list;
  why3_product_groups : why3_product_group_snapshot list;
  why3_product_individual_reasons :
    why3_product_individual_reason_snapshot list;
  why3_smt_fingerprints : string list;
}

(** [reset] service entrypoint. *)

val reset : unit -> unit
(** Reset all counters to zero. *)

val snapshot : unit -> snapshot
(** Read current counter values. *)

val diff : before:snapshot -> after_:snapshot -> snapshot
(** Delta between two snapshots. *)

val add_snapshot : snapshot -> unit
(** Add a snapshot produced by another process to the current counters. *)

val record_why3_worker : why3_worker_snapshot -> unit
(** Add one worker-level Why3 proof summary. *)

val record_ir_pass : ir_pass_snapshot -> unit
(** Add one before/after size snapshot for an IR pass. *)

val record_ir_fact_family : ir_fact_family_snapshot -> unit
(** Add one aggregated IR fact-family generation snapshot. *)

val record_why3_product_group : why3_product_group_snapshot -> unit
(** Add one generated Why3 product-step group size snapshot. *)

val record_why3_product_individual_reason :
  why3_product_individual_reason_snapshot -> unit
(** Add one product-step helper individualization reason counter. *)

val record_frontend_parse : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent parsing/lowering the frontend input. *)

val record_snapshot_build : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent building the verification snapshot. *)

val record_contract_partition : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent partitioning contracts. *)

val record_automata_generation : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent building temporal automata. *)

val record_spot : elapsed_s:float -> unit
(** Add one Spot call and its elapsed wall-clock time. *)

val record_z3 : elapsed_s:float -> unit
(** Add one Z3 simplify call and its elapsed wall-clock time. *)

val record_product : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in product-state exploration. *)

val record_canonical : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in canonical construction/enrichment. *)

val record_pre : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in the Pre IR pass. *)

val record_product_reachability : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in the product-reachability IR pass. *)

val record_post : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in the Post IR pass. *)

val record_temporal_lower : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in the temporal-lowering IR pass. *)

val record_instrumentation_info : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent computing instrumentation metrics. *)

val record_output_artifact : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent building output artifact bundles. *)

val record_output_proof_run : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in the proof runner from outputs assembly. *)

val record_output_map : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent mapping artifacts/proofs to outputs. *)

val record_why_gen : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent generating Why3 text from IR. *)

val record_vc_smt : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent generating VCs and submitting to SMT. *)

val record_why3_setup : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent initializing the Why3 environment. *)

val record_why3_parse : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent parsing generated WhyML. *)

val record_why3_typecheck : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent typing WhyML modules/theories. *)

val record_why3_task_extract : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent extracting top-level Why3 tasks. *)

val record_why3_split_vc : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent applying Why3 VC splitting. *)

val record_why3_prepare : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent preparing Why3 tasks. *)

val record_why3_print : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent printing prepared tasks to SMT-LIB. *)

val record_why3_spawn : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent creating prover calls. *)

val record_why3_wait : elapsed_s:float -> solver_s:float -> unit
(** Add elapsed wall-clock and solver-reported time for one prover result. *)

val record_why3_input_goals : count:int -> unit
(** Add logical Why3 goals submitted to the proof loop before deduplication. *)

val record_why3_duplicate_goal : unit -> unit
(** Count one logical goal proved by reusing an identical SMT task result. *)

val record_why3_fallback : unit -> unit
(** Count one fallback prover attempt after a primary prover non-valid result. *)

val record_why3_smt_fingerprint : string -> unit
(** Record one normalized SMT task fingerprint. *)
