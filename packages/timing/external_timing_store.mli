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

(** Process-local mutable timing store. *)

open External_timing_types

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
