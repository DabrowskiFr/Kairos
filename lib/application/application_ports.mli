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

(** Application-level ports for Kairos use-cases.

    This module defines the dependency inversion boundary used by
    {!Verification_flow_usecases}.  The use-case layer depends on these abstract
    signatures only; concrete implementations are provided by outgoing adapters.
*)

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
  max_cost : int;
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
}

(** One goal result reported by the proof-events port.

    Tuple layout:
    - goal index in the emitted VC order,
    - goal name,
    - textual status,
    - solver time (seconds),
    - optional dump path,
    - optional VC identifier.
*)

type goal_result = int * string * string * float * string option * string option

(** Frontend DTO consumed by application use-cases.

    This payload is language-agnostic: it contains parse metadata and the
    internal verification model needed by subsequent stages.
*)

type frontend_input = {
  imports : string list;
  parse_info : Flow_info.parse_info;
  verification_model : Verification_model.program_model;
}

(** Error type returned by the frontend port. *)

type frontend_error = Pipeline_types.error

val parse_error : string -> frontend_error
val flow_error : string -> frontend_error

(** Port responsible for parsing and lowering one Kairos input source. *)

module type FRONTEND_PORT = sig
  (** Parse and lower [input_file] into a frontend payload. *)
  val parse_input :
    input_file:string ->
    (frontend_input, frontend_error) result
end

(** Port producing an immutable pipeline snapshot from an input file. *)

module type SNAPSHOT_PORT = sig
  (** Opaque snapshot type shared by all other ports. *)

  type snapshot

  (** Build a snapshot from a frontend payload.

      Returns [Error _] when parsing or stage preparation fails.
  *)

  val build_snapshot :
    collect_instrumentation_info:bool ->
    collect_ir_metrics:bool ->
    proof_encoding:Pipeline_types.proof_encoding ->
    proof_optimizations:Pipeline_types.proof_optimizations ->
    frontend:frontend_input ->
    (snapshot, Pipeline_types.error) result
end

(** Port assembling final pipeline outputs from a prepared snapshot. *)

module type OUTPUTS_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Run output assembly for [cfg] on [snapshot]. *)

  val build_outputs :
    cfg:Pipeline_types.config ->
    snapshot:snapshot ->
    (Pipeline_types.outputs, Pipeline_types.error) result
end

(** Port exposing the automata/instrumentation dump pass. *)

module type INSTRUMENTATION_PORT = sig
  (** Run instrumentation artifacts generation for [input_file].

      When [generate_png] is true, PNG rendering is attempted for DOT graphs.
  *)

  val instrumentation_pass :
    generate_png:bool ->
    input_file:string ->
    (Pipeline_types.automata_outputs, Pipeline_types.error) result
end

(** Port generating Why text artifacts from a snapshot. *)

module type WHY_TEXT_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Produce Why text outputs for [snapshot]. *)

  val why_text :
    snapshot:snapshot ->
    Pipeline_types.why_outputs
end

(** Port generating VC/SMT obligations from a snapshot. *)

module type OBLIGATIONS_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Produce VC and SMT textual obligations for [snapshot]. *)

  val obligations :
    snapshot:snapshot ->
    Pipeline_types.obligations_outputs
end

(** Port generating a whole-pipeline proof-cost report. *)

module type COST_REPORT_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Produce a JSON cost report for [snapshot] without running solvers. *)

  val cost_report :
    input_file:string ->
    snapshot:snapshot ->
    (Pipeline_types.cost_report_outputs, Pipeline_types.error) result
end

(** Port exposing textual renderings of the normalized IR. *)

module type IR_RENDER_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Render the normalized program view for [snapshot]. *)

  val normalized_program : snapshot:snapshot -> string
  (** Render the proof-oriented pretty IR view for [snapshot]. *)

  val pretty_program : snapshot:snapshot -> string
end

(** Port exposing external timing counters used by use-cases. *)

module type TIMING_PORT = sig
  (** Opaque timing snapshot captured by the concrete adapter. *)

  type snapshot

  (** Monotonic wall-clock time in seconds used by use-case timing metadata. *)

  val now_s : unit -> float

  (** Capture timing counters at current instant. *)

  val snapshot : unit -> snapshot
  (** Compute elapsed counters between [before] and [after_]. *)

  val diff : before:snapshot -> after_:snapshot -> timing_counters

  val record_frontend_parse : elapsed_s:float -> unit
  (** Add elapsed wall-clock time spent parsing/lowering frontend input. *)

  val record_snapshot_build : elapsed_s:float -> unit
  (** Add elapsed wall-clock time spent building a verification snapshot. *)
end

(** Port executing proof replay with per-goal callbacks. *)

module type PROOF_EVENTS_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Replay proof on [snapshot], emitting [on_goal_done] events in VC order.

      [vc_ids_ordered] maps event indexes to stable VC identifiers.
  *)

  val prove_with_events :
    timeout_s:int ->
    dump_failed_smt:bool ->
    should_cancel:(unit -> bool) ->
    snapshot:snapshot ->
    vc_ids_ordered:int list ->
    on_goal_done:(goal_result -> unit) ->
    goal_result list
end

(** Aggregate of all ports required by pipeline use-cases. *)

module type PORTS = sig
  (** Opaque snapshot type threaded through all sub-ports. *)

  type snapshot

  (** Snapshot construction port. *)

  module Frontend : FRONTEND_PORT
  (** Snapshot construction port. *)

  module Snapshot : SNAPSHOT_PORT with type snapshot = snapshot
  (** Final outputs assembly port. *)

  module Outputs : OUTPUTS_PORT with type snapshot = snapshot
  (** Instrumentation dump port. *)

  module Instrumentation : INSTRUMENTATION_PORT
  (** Why text generation port. *)

  module Why_text : WHY_TEXT_PORT with type snapshot = snapshot
  (** VC/SMT obligations generation port. *)

  module Obligations : OBLIGATIONS_PORT with type snapshot = snapshot
  (** Whole-pipeline cost-report generation port. *)

  module Cost_report : COST_REPORT_PORT with type snapshot = snapshot
  (** IR text rendering port. *)

  module Ir_render : IR_RENDER_PORT with type snapshot = snapshot
  (** Timing counters port. *)

  module Timing : TIMING_PORT
  (** Proof events replay port. *)

  module Proof_events : PROOF_EVENTS_PORT with type snapshot = snapshot
end
