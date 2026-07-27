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

(** Process-local timing counters owned by the Kairos runtime. *)

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
  elaboration_checks_count : int;
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

type snapshot = {
  frontend_parse_s : float;
  snapshot_build_s : float;
  contract_partition_s : float;
  step_projection_s : float;
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
  formula_sharing_s : float;
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
}

(** [reset] service entrypoint. *)

val reset : unit -> unit
(** Reset all counters to zero. *)

val snapshot : unit -> snapshot
(** Read current counter values. *)

val diff : before:snapshot -> after_:snapshot -> snapshot
(** Delta between two snapshots. *)

val record_ir_pass : ir_pass_snapshot -> unit
(** Add one before/after size snapshot for an IR pass. *)

val record_ir_fact_family : ir_fact_family_snapshot -> unit
(** Add one aggregated IR fact-family generation snapshot. *)

val record_frontend_parse : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent parsing/lowering the frontend input. *)

val record_snapshot_build : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent building the verification snapshot. *)

val record_contract_partition : elapsed_s:float -> unit
val record_step_projection : elapsed_s:float -> unit
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
val record_formula_sharing : elapsed_s:float -> unit
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

val record_why3_execution :
  Kairos_why3_contract.Why3_contract.execution_metrics ->
  unit
(** Import the neutral technical measurements returned by one Why3 execution. *)
