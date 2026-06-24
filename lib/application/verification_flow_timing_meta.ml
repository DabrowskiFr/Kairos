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

module Make (P : Application_ports.PORTS) = struct
  let fmt_s = Verification_flow_timing_fields.fmt_s

  let solver_sum_s = Verification_flow_timing_fields.solver_sum_s

  let goal_status_is_pending =
    Verification_flow_timing_fields.goal_status_is_pending

  let why3_worker_timing_fields =
    Verification_flow_timing_fields.why3_worker_timing_fields

  let ir_pass_size_fields =
    Verification_flow_timing_fields.ir_pass_size_fields

  let ir_fact_family_fields =
    Verification_flow_timing_fields.ir_fact_family_fields

  let product_group_fields =
    Verification_flow_timing_fields.product_group_fields

  let product_individual_reason_fields =
    Verification_flow_timing_fields.product_individual_reason_fields

  let vc_taxonomy_fields = Verification_flow_vc_taxonomy.fields

  let with_timing_flow_meta ~(t0 : float) ~(t_build_done : float)
      ~(snap_before : P.Timing.snapshot) (out : Pipeline_types.outputs) :
      Pipeline_types.outputs =
    let t_end = P.Timing.now_s () in
    let counters =
      P.Timing.diff ~before:snap_before ~after_:(P.Timing.snapshot ())
    in
    let solver_s = solver_sum_s out.goals in
    let pending_goal_count =
      List.fold_left
        (fun acc goal -> if goal_status_is_pending goal then acc + 1 else acc)
        0 out.goals
    in
    let attempted_goal_count = List.length out.goals - pending_goal_count in
    let why3_backend_aggregate_s =
      counters.why3_prepare_s +. counters.why3_print_s +. counters.why3_spawn_s
      +. counters.why3_wait_s
    in
    let why3_backend_non_solver_aggregate_s =
      max 0.0 (why3_backend_aggregate_s -. counters.why3_solver_s)
    in
    let why3_task_pipeline_s =
      counters.why3_setup_s +. counters.why3_parse_s
      +. counters.why3_typecheck_s +. counters.why3_task_extract_s
      +. counters.why3_split_vc_s
    in
    let canonical_known_stages_s =
      counters.pre_s +. counters.product_reachability_s +. counters.post_s
      +. counters.temporal_lower_s
    in
    let canonical_unaccounted_s =
      max 0.0 (counters.canonical_s -. canonical_known_stages_s)
    in
    let snapshot_known_stages_s =
      counters.contract_partition_s +. counters.automata_generation_s
      +. counters.product_s +. counters.canonical_s
      +. counters.instrumentation_info_s
    in
    let snapshot_unaccounted_s =
      max 0.0 (counters.snapshot_build_s -. snapshot_known_stages_s)
    in
    let build_ast_unaccounted_s =
      max 0.0
        ((t_build_done -. t0)
        -. counters.frontend_parse_s -. snapshot_known_stages_s)
    in
    let worker_count = List.length counters.why3_workers in
    let worker_wall_sum_s =
      List.fold_left
        (fun acc (worker : Application_ports.why3_worker_counters) ->
          acc +. worker.worker_wall_s)
        0.0 counters.why3_workers
    in
    let worker_wall_max_s =
      List.fold_left
        (fun acc (worker : Application_ports.why3_worker_counters) ->
          max acc worker.worker_wall_s)
        0.0 counters.why3_workers
    in
    let worker_wall_min_s =
      match counters.why3_workers with
      | [] -> 0.0
      | worker :: rest ->
          List.fold_left
            (fun acc (worker : Application_ports.why3_worker_counters) ->
              min acc worker.worker_wall_s)
            worker.worker_wall_s rest
    in
    let worker_wall_imbalance_s =
      max 0.0 (worker_wall_max_s -. worker_wall_min_s)
    in
    let worker_parallel_efficiency =
      if worker_count = 0 || worker_wall_max_s = 0.0 then 0.0
      else worker_wall_sum_s /. (worker_wall_max_s *. float_of_int worker_count)
    in
    let why3_parent_orchestration_s =
      max 0.0 (counters.vc_smt_s -. worker_wall_max_s)
    in
    let why3_cross_worker_duplicate_goal_count =
      max 0
        (counters.why3_smt_fingerprint_count
        - counters.why3_unique_smt_fingerprint_count
        - counters.why3_duplicate_goal_count)
    in
    let worker_timing_fields =
      counters.why3_workers
      |> List.sort
           (fun (left : Application_ports.why3_worker_counters)
                (right : Application_ports.why3_worker_counters) ->
             Int.compare left.worker_id right.worker_id)
      |> List.concat_map why3_worker_timing_fields
    in
    let ir_pass_size_fields =
      counters.ir_passes |> List.concat_map ir_pass_size_fields
    in
    let ir_fact_family_fields =
      counters.ir_fact_families |> List.concat_map ir_fact_family_fields
    in
    let product_group_fields = product_group_fields counters.why3_product_groups in
    let product_individual_reason_fields =
      product_individual_reason_fields
        counters.why3_product_individual_reasons
    in
    let vc_taxonomy_fields = vc_taxonomy_fields out.proof_traces in
    let timing_fields =
      [
        ("total_wall_s", fmt_s (t_end -. t0));
        ("build_ast_s", fmt_s (t_build_done -. t0));
        ("frontend_parse_s", fmt_s counters.frontend_parse_s);
        ("snapshot_build_s", fmt_s counters.snapshot_build_s);
        ("contract_partition_s", fmt_s counters.contract_partition_s);
        ("automata_generation_s", fmt_s counters.automata_generation_s);
        ("build_outputs_s", fmt_s (t_end -. t_build_done));
        ("spot_s", fmt_s counters.spot_s);
        ("spot_calls", string_of_int counters.spot_calls);
        ("z3_s", fmt_s counters.z3_s);
        ("z3_calls", string_of_int counters.z3_calls);
        ("product_s", fmt_s counters.product_s);
        ("canonical_s", fmt_s counters.canonical_s);
        ("pre_s", fmt_s counters.pre_s);
        ("product_reachability_s", fmt_s counters.product_reachability_s);
        ("post_s", fmt_s counters.post_s);
        ("temporal_lower_s", fmt_s counters.temporal_lower_s);
        ("canonical_known_stages_s", fmt_s canonical_known_stages_s);
        ("canonical_unaccounted_s", fmt_s canonical_unaccounted_s);
        ("instrumentation_info_s", fmt_s counters.instrumentation_info_s);
        ("snapshot_known_stages_s", fmt_s snapshot_known_stages_s);
        ("snapshot_unaccounted_s", fmt_s snapshot_unaccounted_s);
        ("build_ast_unaccounted_s", fmt_s build_ast_unaccounted_s);
        ("output_artifact_s", fmt_s counters.output_artifact_s);
        ("output_proof_run_s", fmt_s counters.output_proof_run_s);
        ("output_map_s", fmt_s counters.output_map_s);
        ("why_gen_s", fmt_s counters.why_gen_s);
        ("vc_smt_s", fmt_s counters.vc_smt_s);
        ("why3_worker_count", string_of_int worker_count);
        ("why3_worker_wall_sum_s", fmt_s worker_wall_sum_s);
        ("why3_worker_wall_max_s", fmt_s worker_wall_max_s);
        ("why3_worker_wall_min_s", fmt_s worker_wall_min_s);
        ("why3_worker_wall_imbalance_s", fmt_s worker_wall_imbalance_s);
        ("why3_worker_parallel_efficiency", fmt_s worker_parallel_efficiency);
        ("why3_parent_orchestration_s", fmt_s why3_parent_orchestration_s);
        ("why3_setup_s", fmt_s counters.why3_setup_s);
        ("why3_parse_s", fmt_s counters.why3_parse_s);
        ("why3_typecheck_s", fmt_s counters.why3_typecheck_s);
        ("why3_task_extract_s", fmt_s counters.why3_task_extract_s);
        ("why3_split_vc_s", fmt_s counters.why3_split_vc_s);
        ("why3_task_pipeline_s", fmt_s why3_task_pipeline_s);
        ("why3_prepare_s", fmt_s counters.why3_prepare_s);
        ("why3_print_s", fmt_s counters.why3_print_s);
        ("why3_spawn_s", fmt_s counters.why3_spawn_s);
        ("why3_wait_s", fmt_s counters.why3_wait_s);
        ("why3_solver_s", fmt_s counters.why3_solver_s);
        ("why3_backend_aggregate_s", fmt_s why3_backend_aggregate_s);
        ( "why3_backend_non_solver_aggregate_s",
          fmt_s why3_backend_non_solver_aggregate_s );
        ( "why3_non_solver_overhead_s",
          fmt_s (max 0.0 (counters.vc_smt_s -. counters.why3_solver_s)) );
        ("why3_input_goal_count", string_of_int counters.why3_input_goal_count);
        ("why3_goal_count", string_of_int counters.why3_goal_count);
        ( "why3_duplicate_goal_count",
          string_of_int counters.why3_duplicate_goal_count );
        ("why3_fallback_count", string_of_int counters.why3_fallback_count);
        ( "why3_smt_fingerprint_count",
          string_of_int counters.why3_smt_fingerprint_count );
        ( "why3_unique_smt_fingerprint_count",
          string_of_int counters.why3_unique_smt_fingerprint_count );
        ( "why3_cross_worker_duplicate_goal_count",
          string_of_int why3_cross_worker_duplicate_goal_count );
        ("solver_sum_s", fmt_s solver_s);
        ("solver_goal_count", string_of_int attempted_goal_count);
        ("pending_goal_count", string_of_int pending_goal_count);
      ]
      @ vc_taxonomy_fields
      @ product_group_fields
      @ product_individual_reason_fields
      @ ir_pass_size_fields
      @ ir_fact_family_fields
      @ worker_timing_fields
    in
    { out with flow_meta = out.flow_meta @ [ ("timings", timing_fields) ] }
end
