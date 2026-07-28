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

(** Process-local mutable timing store owned by the Kairos runtime. *)

open Runtime_metrics_types

let frontend_parse_s = ref 0.0
let snapshot_build_s = ref 0.0
let contract_partition_s = ref 0.0
let proof_planning_s = ref 0.0
let automata_generation_s = ref 0.0
let spot_s = ref 0.0
let spot_calls = ref 0
let z3_s = ref 0.0
let z3_calls = ref 0
let product_s = ref 0.0
let canonical_s = ref 0.0
let pre_s = ref 0.0
let product_reachability_s = ref 0.0
let post_s = ref 0.0
let temporal_lower_s = ref 0.0
let instrumentation_info_s = ref 0.0
let output_artifact_s = ref 0.0
let output_proof_run_s = ref 0.0
let output_map_s = ref 0.0
let why_gen_s = ref 0.0
let vc_smt_s = ref 0.0
let why3_setup_s = ref 0.0
let why3_parse_s = ref 0.0
let why3_typecheck_s = ref 0.0
let why3_task_extract_s = ref 0.0
let why3_split_vc_s = ref 0.0
let why3_prepare_s = ref 0.0
let why3_print_s = ref 0.0
let why3_spawn_s = ref 0.0
let why3_wait_s = ref 0.0
let why3_solver_s = ref 0.0
let why3_input_goal_count = ref 0
let why3_goal_count = ref 0
let why3_duplicate_goal_count = ref 0
let why3_fallback_count = ref 0
let why3_smt_fingerprint_count = ref 0
let why3_unique_smt_fingerprint_count = ref 0
let why3_workers = ref []
let ir_passes = ref []
let ir_fact_families = ref []

let reset () =
  frontend_parse_s := 0.0;
  snapshot_build_s := 0.0;
  contract_partition_s := 0.0;
  proof_planning_s := 0.0;
  automata_generation_s := 0.0;
  spot_s := 0.0;
  spot_calls := 0;
  z3_s := 0.0;
  z3_calls := 0;
  product_s := 0.0;
  canonical_s := 0.0;
  pre_s := 0.0;
  product_reachability_s := 0.0;
  post_s := 0.0;
  temporal_lower_s := 0.0;
  instrumentation_info_s := 0.0;
  output_artifact_s := 0.0;
  output_proof_run_s := 0.0;
  output_map_s := 0.0;
  why_gen_s := 0.0;
  vc_smt_s := 0.0;
  why3_setup_s := 0.0;
  why3_parse_s := 0.0;
  why3_typecheck_s := 0.0;
  why3_task_extract_s := 0.0;
  why3_split_vc_s := 0.0;
  why3_prepare_s := 0.0;
  why3_print_s := 0.0;
  why3_spawn_s := 0.0;
  why3_wait_s := 0.0;
  why3_solver_s := 0.0;
  why3_input_goal_count := 0;
  why3_goal_count := 0;
  why3_duplicate_goal_count := 0;
  why3_fallback_count := 0;
  why3_smt_fingerprint_count := 0;
  why3_unique_smt_fingerprint_count := 0;
  why3_workers := [];
  ir_passes := [];
  ir_fact_families := []

let snapshot () : snapshot =
  {
    frontend_parse_s = !frontend_parse_s;
    snapshot_build_s = !snapshot_build_s;
    contract_partition_s = !contract_partition_s;
    proof_planning_s = !proof_planning_s;
    automata_generation_s = !automata_generation_s;
    spot_s = !spot_s;
    spot_calls = !spot_calls;
    z3_s = !z3_s;
    z3_calls = !z3_calls;
    product_s = !product_s;
    canonical_s = !canonical_s;
    pre_s = !pre_s;
    product_reachability_s = !product_reachability_s;
    post_s = !post_s;
    temporal_lower_s = !temporal_lower_s;
    instrumentation_info_s = !instrumentation_info_s;
    output_artifact_s = !output_artifact_s;
    output_proof_run_s = !output_proof_run_s;
    output_map_s = !output_map_s;
    why_gen_s = !why_gen_s;
    vc_smt_s = !vc_smt_s;
    why3_setup_s = !why3_setup_s;
    why3_parse_s = !why3_parse_s;
    why3_typecheck_s = !why3_typecheck_s;
    why3_task_extract_s = !why3_task_extract_s;
    why3_split_vc_s = !why3_split_vc_s;
    why3_prepare_s = !why3_prepare_s;
    why3_print_s = !why3_print_s;
    why3_spawn_s = !why3_spawn_s;
    why3_wait_s = !why3_wait_s;
    why3_solver_s = !why3_solver_s;
    why3_input_goal_count = !why3_input_goal_count;
    why3_goal_count = !why3_goal_count;
    why3_duplicate_goal_count = !why3_duplicate_goal_count;
    why3_fallback_count = !why3_fallback_count;
    why3_smt_fingerprint_count = !why3_smt_fingerprint_count;
    why3_unique_smt_fingerprint_count =
      !why3_unique_smt_fingerprint_count;
    why3_workers = List.rev !why3_workers;
    ir_passes = List.rev !ir_passes;
    ir_fact_families = List.rev !ir_fact_families;
  }

let rec drop_prefix n xs =
  if n <= 0 then xs
  else match xs with [] -> [] | _ :: rest -> drop_prefix (n - 1) rest

let diff ~before ~(after_ : snapshot) : snapshot =
  {
    frontend_parse_s =
      max 0.0 (after_.frontend_parse_s -. before.frontend_parse_s);
    snapshot_build_s =
      max 0.0 (after_.snapshot_build_s -. before.snapshot_build_s);
    contract_partition_s =
      max 0.0 (after_.contract_partition_s -. before.contract_partition_s);
    proof_planning_s =
      max 0.0 (after_.proof_planning_s -. before.proof_planning_s);
    automata_generation_s =
      max 0.0 (after_.automata_generation_s -. before.automata_generation_s);
    spot_s = max 0.0 (after_.spot_s -. before.spot_s);
    spot_calls = max 0 (after_.spot_calls - before.spot_calls);
    z3_s = max 0.0 (after_.z3_s -. before.z3_s);
    z3_calls = max 0 (after_.z3_calls - before.z3_calls);
    product_s = max 0.0 (after_.product_s -. before.product_s);
    canonical_s = max 0.0 (after_.canonical_s -. before.canonical_s);
    pre_s = max 0.0 (after_.pre_s -. before.pre_s);
    product_reachability_s =
      max 0.0
        (after_.product_reachability_s -. before.product_reachability_s);
    post_s = max 0.0 (after_.post_s -. before.post_s);
    temporal_lower_s =
      max 0.0 (after_.temporal_lower_s -. before.temporal_lower_s);
    instrumentation_info_s =
      max 0.0 (after_.instrumentation_info_s -. before.instrumentation_info_s);
    output_artifact_s =
      max 0.0 (after_.output_artifact_s -. before.output_artifact_s);
    output_proof_run_s =
      max 0.0 (after_.output_proof_run_s -. before.output_proof_run_s);
    output_map_s = max 0.0 (after_.output_map_s -. before.output_map_s);
    why_gen_s = max 0.0 (after_.why_gen_s -. before.why_gen_s);
    vc_smt_s = max 0.0 (after_.vc_smt_s -. before.vc_smt_s);
    why3_setup_s = max 0.0 (after_.why3_setup_s -. before.why3_setup_s);
    why3_parse_s = max 0.0 (after_.why3_parse_s -. before.why3_parse_s);
    why3_typecheck_s =
      max 0.0 (after_.why3_typecheck_s -. before.why3_typecheck_s);
    why3_task_extract_s =
      max 0.0 (after_.why3_task_extract_s -. before.why3_task_extract_s);
    why3_split_vc_s = max 0.0 (after_.why3_split_vc_s -. before.why3_split_vc_s);
    why3_prepare_s = max 0.0 (after_.why3_prepare_s -. before.why3_prepare_s);
    why3_print_s = max 0.0 (after_.why3_print_s -. before.why3_print_s);
    why3_spawn_s = max 0.0 (after_.why3_spawn_s -. before.why3_spawn_s);
    why3_wait_s = max 0.0 (after_.why3_wait_s -. before.why3_wait_s);
    why3_solver_s = max 0.0 (after_.why3_solver_s -. before.why3_solver_s);
    why3_input_goal_count =
      max 0 (after_.why3_input_goal_count - before.why3_input_goal_count);
    why3_goal_count = max 0 (after_.why3_goal_count - before.why3_goal_count);
    why3_duplicate_goal_count =
      max 0 (after_.why3_duplicate_goal_count - before.why3_duplicate_goal_count);
    why3_fallback_count =
      max 0 (after_.why3_fallback_count - before.why3_fallback_count);
    why3_smt_fingerprint_count =
      max 0
        (after_.why3_smt_fingerprint_count
        - before.why3_smt_fingerprint_count);
    why3_unique_smt_fingerprint_count =
      max 0
        (after_.why3_unique_smt_fingerprint_count
        - before.why3_unique_smt_fingerprint_count);
    why3_workers =
      after_.why3_workers
      |> List.filter (fun worker ->
             not
               (List.exists
                  (fun before_worker ->
                    before_worker.worker_id = worker.worker_id
                    && before_worker.worker_wall_s = worker.worker_wall_s
                    && before_worker.worker_last_goal = worker.worker_last_goal)
                  before.why3_workers));
    ir_passes = drop_prefix (List.length before.ir_passes) after_.ir_passes;
    ir_fact_families =
      drop_prefix
        (List.length before.ir_fact_families)
        after_.ir_fact_families;
  }

let record_ir_pass pass = ir_passes := pass :: !ir_passes

let record_ir_fact_family family =
  ir_fact_families := family :: !ir_fact_families

let record_frontend_parse ~elapsed_s =
  frontend_parse_s := !frontend_parse_s +. max 0.0 elapsed_s

let record_snapshot_build ~elapsed_s =
  snapshot_build_s := !snapshot_build_s +. max 0.0 elapsed_s

let record_contract_partition ~elapsed_s =
  contract_partition_s := !contract_partition_s +. max 0.0 elapsed_s

let record_proof_planning ~elapsed_s =
  proof_planning_s := !proof_planning_s +. max 0.0 elapsed_s

let record_automata_generation ~elapsed_s =
  automata_generation_s := !automata_generation_s +. max 0.0 elapsed_s

let record_spot ~elapsed_s =
  incr spot_calls;
  spot_s := !spot_s +. max 0.0 elapsed_s

let record_z3 ~elapsed_s =
  incr z3_calls;
  z3_s := !z3_s +. max 0.0 elapsed_s

let record_product ~elapsed_s = product_s := !product_s +. max 0.0 elapsed_s

let record_canonical ~elapsed_s = canonical_s := !canonical_s +. max 0.0 elapsed_s

let record_pre ~elapsed_s = pre_s := !pre_s +. max 0.0 elapsed_s

let record_product_reachability ~elapsed_s =
  product_reachability_s := !product_reachability_s +. max 0.0 elapsed_s

let record_post ~elapsed_s = post_s := !post_s +. max 0.0 elapsed_s

let record_temporal_lower ~elapsed_s =
  temporal_lower_s := !temporal_lower_s +. max 0.0 elapsed_s

let record_instrumentation_info ~elapsed_s =
  instrumentation_info_s := !instrumentation_info_s +. max 0.0 elapsed_s

let record_output_artifact ~elapsed_s =
  output_artifact_s := !output_artifact_s +. max 0.0 elapsed_s

let record_output_proof_run ~elapsed_s =
  output_proof_run_s := !output_proof_run_s +. max 0.0 elapsed_s

let record_output_map ~elapsed_s =
  output_map_s := !output_map_s +. max 0.0 elapsed_s

let record_why_gen ~elapsed_s = why_gen_s := !why_gen_s +. max 0.0 elapsed_s

let record_vc_smt ~elapsed_s = vc_smt_s := !vc_smt_s +. max 0.0 elapsed_s

let record_why3_execution
    (metrics :
      Kairos_why3_contract.Why3_contract.execution_metrics) =
  why3_setup_s := !why3_setup_s +. max 0.0 metrics.setup_s;
  why3_parse_s := !why3_parse_s +. max 0.0 metrics.parse_s;
  why3_typecheck_s := !why3_typecheck_s +. max 0.0 metrics.typecheck_s;
  why3_task_extract_s :=
    !why3_task_extract_s +. max 0.0 metrics.task_extract_s;
  why3_split_vc_s := !why3_split_vc_s +. max 0.0 metrics.split_vc_s;
  why3_prepare_s := !why3_prepare_s +. max 0.0 metrics.prepare_s;
  why3_print_s := !why3_print_s +. max 0.0 metrics.print_s;
  why3_spawn_s := !why3_spawn_s +. max 0.0 metrics.spawn_s;
  why3_wait_s := !why3_wait_s +. max 0.0 metrics.wait_s;
  why3_solver_s := !why3_solver_s +. max 0.0 metrics.solver_s;
  why3_input_goal_count :=
    !why3_input_goal_count + max 0 metrics.input_goal_count;
  why3_goal_count := !why3_goal_count + max 0 metrics.prover_goal_count;
  why3_duplicate_goal_count :=
    !why3_duplicate_goal_count + max 0 metrics.duplicate_goal_count;
  why3_fallback_count :=
    !why3_fallback_count + max 0 metrics.fallback_count;
  why3_smt_fingerprint_count :=
    !why3_smt_fingerprint_count + max 0 metrics.smt_fingerprint_count;
  why3_unique_smt_fingerprint_count :=
    !why3_unique_smt_fingerprint_count
    + max 0 metrics.unique_smt_fingerprint_count;
  let workers =
    List.map
      (fun
        (worker :
          Kairos_why3_contract.Why3_contract.worker_metrics) ->
        {
          worker_id = worker.worker_id;
          worker_input_goal_count = worker.input_goal_count;
          worker_prover_goal_count = worker.prover_goal_count;
          worker_duplicate_goal_count = worker.duplicate_goal_count;
          worker_fallback_count = worker.fallback_count;
          worker_wall_s = worker.wall_s;
          worker_prepare_s = worker.prepare_s;
          worker_print_s = worker.print_s;
          worker_spawn_s = worker.spawn_s;
          worker_wait_s = worker.wait_s;
          worker_solver_s = worker.solver_s;
          worker_last_goal = worker.last_goal;
        })
      metrics.workers
  in
  why3_workers := List.rev_append workers !why3_workers
