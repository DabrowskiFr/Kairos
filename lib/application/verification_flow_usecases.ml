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
  let ( let* ) = Result.bind

  let fmt_s x = Printf.sprintf "%.6f" x

  let bool_s = function true -> "true" | false -> "false"

  let sanitize_csv_value value =
    String.map
      (function
        | ',' | '\n' | '\r' -> ';'
        | '"' -> '\''
        | c -> c)
      value

  let solver_sum_s (goals : Pipeline_types.goal_info list) : float =
    List.fold_left (fun acc (_, _, time_s, _, _) -> acc +. time_s) 0.0 goals

  let goal_status_is_pending (_, status, _, _, _) =
    String.lowercase_ascii status = "pending"

  let is_minimal_prove_run (cfg : Pipeline_types.config) : bool =
    cfg.prove && not cfg.wp_only && not cfg.compute_proof_diagnostics
    && not cfg.generate_vc_text && not cfg.generate_smt_text
    && not cfg.generate_dot_png && Option.is_none cfg.proof_progress_path

  let why3_worker_timing_fields (worker : Application_ports.why3_worker_counters) =
    let prefix = Printf.sprintf "why3_worker_%d_" worker.worker_id in
    [
      (prefix ^ "input_goal_count", string_of_int worker.worker_input_goal_count);
      (prefix ^ "prover_goal_count", string_of_int worker.worker_prover_goal_count);
      ( prefix ^ "duplicate_goal_count",
        string_of_int worker.worker_duplicate_goal_count );
      (prefix ^ "fallback_count", string_of_int worker.worker_fallback_count);
      (prefix ^ "wall_s", fmt_s worker.worker_wall_s);
      (prefix ^ "prepare_s", fmt_s worker.worker_prepare_s);
      (prefix ^ "print_s", fmt_s worker.worker_print_s);
      (prefix ^ "spawn_s", fmt_s worker.worker_spawn_s);
      (prefix ^ "wait_s", fmt_s worker.worker_wait_s);
      (prefix ^ "solver_s", fmt_s worker.worker_solver_s);
      (prefix ^ "last_goal", worker.worker_last_goal);
    ]

  let ir_size_count (name : string) (size : Application_ports.ir_size_metrics) :
      int =
    match name with
    | "node_count" -> size.node_count
    | "summary_count" -> size.summary_count
    | "safe_case_count" -> size.safe_case_count
    | "unsafe_case_count" -> size.unsafe_case_count
    | "propagation_requires_count" -> size.propagation_requires_count
    | "requires_count" -> size.requires_count
    | "ensures_count" -> size.ensures_count
    | "init_invariant_goal_count" -> size.init_invariant_goal_count
    | "formula_occurrence_count" -> size.formula_occurrence_count
    | "unique_formula_count" -> size.unique_formula_count
    | "duplicated_formula_occurrence_count" ->
        size.formula_occurrence_count - size.unique_formula_count
    | _ -> invalid_arg ("unknown IR size metric: " ^ name)

  let ir_pass_size_fields (pass : Application_ports.ir_pass_counters) =
    let prefix = "ir_" ^ pass.pass_name ^ "_" in
    [
      "node_count";
      "summary_count";
      "safe_case_count";
      "unsafe_case_count";
      "propagation_requires_count";
      "requires_count";
      "ensures_count";
      "init_invariant_goal_count";
      "formula_occurrence_count";
      "unique_formula_count";
      "duplicated_formula_occurrence_count";
    ]
    |> List.concat_map (fun metric ->
           let before = ir_size_count metric pass.before in
           let after_ = ir_size_count metric pass.after_ in
           [
             (prefix ^ "before_" ^ metric, string_of_int before);
             (prefix ^ "after_" ^ metric, string_of_int after_);
             (prefix ^ "delta_" ^ metric, string_of_int (after_ - before));
           ])

  let ir_fact_family_fields (family : Application_ports.ir_fact_family_counters) =
    let prefix =
      "ir_family_" ^ family.pass_name ^ "_" ^ family.family_name ^ "_"
    in
    [
      ("candidate_count", family.candidate_count);
      ("inserted_count", family.inserted_count);
      ("unique_candidate_count", family.unique_candidate_count);
      ("unique_inserted_count", family.unique_inserted_count);
      ( "duplicate_candidate_count",
        family.candidate_count - family.unique_candidate_count );
      ( "duplicate_inserted_count",
        family.inserted_count - family.unique_inserted_count );
    ]
    |> List.map (fun (name, count) -> (prefix ^ name, string_of_int count))

  let product_group_fields
      (groups : Application_ports.why3_product_group_counters list) =
    let emitted_as_group
        (group : Application_ports.why3_product_group_counters) =
      group.emitted_as_group
    in
    let split_due_to_cost
        (group : Application_ports.why3_product_group_counters) =
      group.split_due_to_cost
    in
    let group_name (group : Application_ports.why3_product_group_counters) =
      group.group_name
    in
    let node_name (group : Application_ports.why3_product_group_counters) =
      group.node_name
    in
    let transition_id
        (group : Application_ports.why3_product_group_counters) =
      group.transition_id
    in
    let step_class (group : Application_ports.why3_product_group_counters) =
      group.step_class
    in
    let source_state (group : Application_ports.why3_product_group_counters) =
      group.source_state
    in
    let edge_count (group : Application_ports.why3_product_group_counters) =
      group.edge_count
    in
    let distinct_pre_count
        (group : Application_ports.why3_product_group_counters) =
      group.distinct_pre_count
    in
    let distinct_post_count
        (group : Application_ports.why3_product_group_counters) =
      group.distinct_post_count
    in
    let post_implication_count
        (group : Application_ports.why3_product_group_counters) =
      group.post_implication_count
    in
    let pre_text_bytes
        (group : Application_ports.why3_product_group_counters) =
      group.pre_text_bytes
    in
    let post_text_bytes
        (group : Application_ports.why3_product_group_counters) =
      group.post_text_bytes
    in
    let estimated_cost
        (group : Application_ports.why3_product_group_counters) =
      group.estimated_cost
    in
    let max_cost (group : Application_ports.why3_product_group_counters) =
      group.max_cost
    in
    let sum_by f = List.fold_left (fun acc group -> acc + f group) 0 groups in
    let max_by f = List.fold_left (fun acc group -> max acc (f group)) 0 groups in
    let emitted_group_count =
      List.fold_left
        (fun acc group -> if emitted_as_group group then acc + 1 else acc)
        0 groups
    in
    let split_group_count =
      List.fold_left
        (fun acc group -> if split_due_to_cost group then acc + 1 else acc)
        0 groups
    in
    let top_groups =
      groups
      |> List.sort (fun left right ->
             match Int.compare (estimated_cost right) (estimated_cost left) with
             | 0 -> Int.compare (edge_count right) (edge_count left)
             | cmp -> cmp)
      |> List.filteri (fun index _ -> index < 20)
      |> List.mapi (fun index group ->
             let prefix =
               Printf.sprintf "why3_product_group_top_%03d_" (index + 1)
             in
             [
               (prefix ^ "name", sanitize_csv_value (group_name group));
               (prefix ^ "node", sanitize_csv_value (node_name group));
               (prefix ^ "transition", sanitize_csv_value (transition_id group));
               (prefix ^ "step_class", sanitize_csv_value (step_class group));
               (prefix ^ "source_state", sanitize_csv_value (source_state group));
               (prefix ^ "emitted_as_group", bool_s (emitted_as_group group));
               (prefix ^ "split_due_to_cost", bool_s (split_due_to_cost group));
               (prefix ^ "edge_count", string_of_int (edge_count group));
               (prefix ^ "distinct_pre_count", string_of_int (distinct_pre_count group));
               (prefix ^ "distinct_post_count", string_of_int (distinct_post_count group));
               ( prefix ^ "post_implication_count",
                 string_of_int (post_implication_count group) );
               (prefix ^ "pre_text_bytes", string_of_int (pre_text_bytes group));
               (prefix ^ "post_text_bytes", string_of_int (post_text_bytes group));
               (prefix ^ "estimated_cost", string_of_int (estimated_cost group));
               (prefix ^ "max_cost", string_of_int (max_cost group));
             ])
      |> List.concat
    in
    [
      ("why3_product_group_count", string_of_int (List.length groups));
      ("why3_product_group_emitted_count", string_of_int emitted_group_count);
      ("why3_product_group_split_count", string_of_int split_group_count);
      ("why3_product_group_edge_count", string_of_int (sum_by edge_count));
      ( "why3_product_group_max_edge_count",
        string_of_int (max_by edge_count) );
      ( "why3_product_group_max_distinct_pre_count",
        string_of_int (max_by distinct_pre_count) );
      ( "why3_product_group_max_distinct_post_count",
        string_of_int (max_by distinct_post_count) );
      ( "why3_product_group_max_post_implication_count",
        string_of_int (max_by post_implication_count) );
      ( "why3_product_group_max_pre_text_bytes",
        string_of_int (max_by pre_text_bytes) );
      ( "why3_product_group_max_post_text_bytes",
        string_of_int (max_by post_text_bytes) );
      ( "why3_product_group_max_estimated_cost",
        string_of_int (max_by estimated_cost) );
    ]
    @ top_groups

  type vc_taxonomy_acc = {
    mutable goal_count : int;
    mutable valid_count : int;
    mutable invalid_count : int;
    mutable timeout_count : int;
    mutable unknown_count : int;
    mutable failure_count : int;
    mutable pending_count : int;
    mutable prepare_s : float;
    mutable print_s : float;
    mutable spawn_s : float;
    mutable wait_s : float;
    mutable solver_s : float;
    mutable sample_goal : string;
  }

  let empty_vc_taxonomy_acc sample_goal =
    {
      goal_count = 0;
      valid_count = 0;
      invalid_count = 0;
      timeout_count = 0;
      unknown_count = 0;
      failure_count = 0;
      pending_count = 0;
      prepare_s = 0.0;
      print_s = 0.0;
      spawn_s = 0.0;
      wait_s = 0.0;
      solver_s = 0.0;
      sample_goal;
    }

  let opt_value = function Some value -> value | None -> ""

  let add_trace_to_vc_taxonomy acc (trace : Pipeline_types.proof_trace) =
    acc.goal_count <- acc.goal_count + 1;
    begin
      match String.lowercase_ascii trace.status with
      | "valid" | "proved" -> acc.valid_count <- acc.valid_count + 1
      | "invalid" -> acc.invalid_count <- acc.invalid_count + 1
      | "timeout" -> acc.timeout_count <- acc.timeout_count + 1
      | "unknown" -> acc.unknown_count <- acc.unknown_count + 1
      | "pending" -> acc.pending_count <- acc.pending_count + 1
      | _ -> acc.failure_count <- acc.failure_count + 1
    end;
    acc.prepare_s <- acc.prepare_s +. trace.why3_prepare_s;
    acc.print_s <- acc.print_s +. trace.why3_print_s;
    acc.spawn_s <- acc.spawn_s +. trace.why3_spawn_s;
    acc.wait_s <- acc.wait_s +. trace.why3_wait_s;
    acc.solver_s <- acc.solver_s +. trace.why3_solver_s

  let grouped_vc_taxonomy traces key_of_trace =
    let table = Hashtbl.create 64 in
    List.iter
      (fun (trace : Pipeline_types.proof_trace) ->
        let key = key_of_trace trace in
        let acc =
          match Hashtbl.find_opt table key with
          | Some acc -> acc
          | None ->
              let acc = empty_vc_taxonomy_acc trace.goal_name in
              Hashtbl.add table key acc;
              acc
        in
        add_trace_to_vc_taxonomy acc trace)
      traces;
    Hashtbl.to_seq table |> List.of_seq
    |> List.sort (fun (_key_a, acc_a) (_key_b, acc_b) ->
           match Int.compare acc_b.goal_count acc_a.goal_count with
           | 0 -> Float.compare acc_b.prepare_s acc_a.prepare_s
           | cmp -> cmp)

  let vc_taxonomy_summary_fields ~prefix ~rank labels acc =
    let row_prefix = Printf.sprintf "%s_%03d_" prefix rank in
    let label_fields =
      labels
      |> List.map (fun (name, value) ->
             (row_prefix ^ name, sanitize_csv_value value))
    in
    label_fields
    @ [
        (row_prefix ^ "goal_count", string_of_int acc.goal_count);
        (row_prefix ^ "valid_count", string_of_int acc.valid_count);
        (row_prefix ^ "invalid_count", string_of_int acc.invalid_count);
        (row_prefix ^ "timeout_count", string_of_int acc.timeout_count);
        (row_prefix ^ "unknown_count", string_of_int acc.unknown_count);
        (row_prefix ^ "failure_count", string_of_int acc.failure_count);
        (row_prefix ^ "pending_count", string_of_int acc.pending_count);
        (row_prefix ^ "prepare_s", fmt_s acc.prepare_s);
        (row_prefix ^ "print_s", fmt_s acc.print_s);
        (row_prefix ^ "spawn_s", fmt_s acc.spawn_s);
        (row_prefix ^ "wait_s", fmt_s acc.wait_s);
        (row_prefix ^ "solver_s", fmt_s acc.solver_s);
        (row_prefix ^ "sample_goal", sanitize_csv_value acc.sample_goal);
      ]

  let vc_taxonomy_fields (traces : Pipeline_types.proof_trace list) =
    let family_groups =
      grouped_vc_taxonomy traces (fun trace ->
          ( trace.obligation_kind,
            opt_value trace.obligation_family,
            opt_value trace.obligation_category ))
      |> List.mapi (fun idx ((kind, family, category), acc) ->
             vc_taxonomy_summary_fields ~prefix:"vc_taxonomy_family"
               ~rank:(idx + 1)
               [ ("kind", kind); ("family", family); ("category", category) ]
               acc)
      |> List.concat
    in
    let transition_groups =
      grouped_vc_taxonomy traces (fun trace ->
          ( trace.obligation_kind,
            opt_value trace.node,
            opt_value trace.transition,
            opt_value trace.obligation_category ))
      |> List.mapi (fun idx ((kind, node, transition, category), acc) ->
             vc_taxonomy_summary_fields ~prefix:"vc_taxonomy_transition"
               ~rank:(idx + 1)
               [
                 ("kind", kind);
                 ("node", node);
                 ("transition", transition);
                 ("category", category);
               ]
               acc)
      |> List.concat
    in
    let source_groups =
      grouped_vc_taxonomy traces (fun trace ->
          ( trace.obligation_kind,
            opt_value trace.node,
            opt_value trace.transition,
            trace.source ))
      |> List.mapi (fun idx ((kind, node, transition, source), acc) ->
             vc_taxonomy_summary_fields ~prefix:"vc_taxonomy_source"
               ~rank:(idx + 1)
               [
                 ("kind", kind);
                 ("node", node);
                 ("transition", transition);
                 ("source", source);
               ]
               acc)
      |> List.concat
    in
    [
      ("vc_taxonomy_goal_count", string_of_int (List.length traces));
      ( "vc_taxonomy_family_group_count",
        string_of_int
          (List.length
             (grouped_vc_taxonomy traces (fun trace ->
                  ( trace.obligation_kind,
                    opt_value trace.obligation_family,
                    opt_value trace.obligation_category ))) ));
      ( "vc_taxonomy_transition_group_count",
        string_of_int
          (List.length
             (grouped_vc_taxonomy traces (fun trace ->
                  ( trace.obligation_kind,
                    opt_value trace.node,
                    opt_value trace.transition,
                    opt_value trace.obligation_category ))) ));
      ( "vc_taxonomy_source_group_count",
        string_of_int
          (List.length
             (grouped_vc_taxonomy traces (fun trace ->
                  ( trace.obligation_kind,
                    opt_value trace.node,
                    opt_value trace.transition,
                    trace.source ))) ));
    ]
    @ family_groups @ transition_groups @ source_groups

  let with_timing_flow_meta ~(t0 : float) ~(t_build_done : float)
      ~(snap_before : P.Timing.snapshot) (out : Pipeline_types.outputs) : Pipeline_types.outputs =
    let t_end = P.Timing.now_s () in
    let counters = P.Timing.diff ~before:snap_before ~after_:(P.Timing.snapshot ()) in
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
          fmt_s
            (max 0.0
               (counters.vc_smt_s -. counters.why3_solver_s)) );
        ("why3_input_goal_count", string_of_int counters.why3_input_goal_count);
        ("why3_goal_count", string_of_int counters.why3_goal_count);
        ("why3_duplicate_goal_count", string_of_int counters.why3_duplicate_goal_count);
        ("why3_fallback_count", string_of_int counters.why3_fallback_count);
        ("why3_smt_fingerprint_count", string_of_int counters.why3_smt_fingerprint_count);
        ( "why3_unique_smt_fingerprint_count",
          string_of_int counters.why3_unique_smt_fingerprint_count );
        ("solver_sum_s", fmt_s solver_s);
        ("solver_goal_count", string_of_int attempted_goal_count);
        ("pending_goal_count", string_of_int pending_goal_count);
      ]
      @ vc_taxonomy_fields
      @ product_group_fields
      @ ir_pass_size_fields
      @ ir_fact_family_fields
      @ worker_timing_fields
    in
    { out with flow_meta = out.flow_meta @ [ ("timings", timing_fields) ] }

  let instrumentation_pass = P.Instrumentation.instrumentation_pass

  let why_pass ~proof_encoding ~proof_optimizations ~input_file =
    let* frontend = P.Frontend.parse_input ~input_file in
    let* snapshot =
      P.Snapshot.build_snapshot ~proof_encoding ~proof_optimizations ~frontend
        ~collect_instrumentation_info:true ~collect_ir_metrics:false
    in
    Ok (P.Why_text.why_text ~snapshot)

  let obligations_pass ~proof_encoding ~proof_optimizations ~input_file =
    let* frontend = P.Frontend.parse_input ~input_file in
    let* snapshot =
      P.Snapshot.build_snapshot ~proof_encoding ~proof_optimizations ~frontend
        ~collect_instrumentation_info:true ~collect_ir_metrics:false
    in
    Ok (P.Obligations.obligations ~snapshot)

  let cost_report ~proof_encoding ~proof_optimizations ~input_file =
    let* frontend = P.Frontend.parse_input ~input_file in
    let* snapshot =
      P.Snapshot.build_snapshot ~proof_encoding ~proof_optimizations ~frontend
        ~collect_instrumentation_info:true ~collect_ir_metrics:false
    in
    P.Cost_report.cost_report ~input_file ~snapshot

  let normalized_program ~proof_encoding ~proof_optimizations ~input_file =
    let* frontend = P.Frontend.parse_input ~input_file in
    let* snapshot =
      P.Snapshot.build_snapshot ~proof_encoding ~proof_optimizations ~frontend
        ~collect_instrumentation_info:true ~collect_ir_metrics:false
    in
    Ok (P.Ir_render.normalized_program ~snapshot)

  let ir_pretty_dump ~proof_encoding ~proof_optimizations ~input_file =
    let* frontend = P.Frontend.parse_input ~input_file in
    let* snapshot =
      P.Snapshot.build_snapshot ~proof_encoding ~proof_optimizations ~frontend
        ~collect_instrumentation_info:true ~collect_ir_metrics:false
    in
    Ok (P.Ir_render.pretty_program ~snapshot)

  let run (cfg : Pipeline_types.config) =
    let t0 = P.Timing.now_s () in
    let snap_before = P.Timing.snapshot () in
    let t_parse = P.Timing.now_s () in
    let* frontend = P.Frontend.parse_input ~input_file:cfg.input_file in
    P.Timing.record_frontend_parse ~elapsed_s:(P.Timing.now_s () -. t_parse);
    let t_snapshot = P.Timing.now_s () in
    let* snapshot =
      P.Snapshot.build_snapshot ~proof_encoding:cfg.proof_encoding
        ~proof_optimizations:cfg.proof_optimizations ~frontend
        ~collect_instrumentation_info:(not (is_minimal_prove_run cfg))
        ~collect_ir_metrics:cfg.collect_ir_metrics
    in
        P.Timing.record_snapshot_build ~elapsed_s:(P.Timing.now_s () -. t_snapshot);
        let t_build_done = P.Timing.now_s () in
        (match P.Outputs.build_outputs ~cfg ~snapshot with
        | Error _ as e -> e
        | Ok out -> Ok (with_timing_flow_meta ~t0 ~t_build_done ~snap_before out))

  let run_with_callbacks ~should_cancel (cfg : Pipeline_types.config) ~on_outputs_ready ~on_goals_ready
      ~on_goal_done =
    if cfg.compute_proof_diagnostics then
      match run cfg with
      | Error _ as e -> e
      | Ok (out : Pipeline_types.outputs) ->
          on_outputs_ready { out with goals = [] };
          let goal_names = List.map (fun (g, _, _, _, _) -> g) out.goals in
          let vc_ids = List.init (List.length out.goals) (fun i -> i + 1) in
          on_goals_ready (goal_names, vc_ids);
          List.iteri
            (fun i (goal, status, time_s, dump_path, vcid) ->
              on_goal_done i goal status time_s dump_path vcid)
            out.goals;
          if should_cancel () then Error (Pipeline_types.Flow_error "Request cancelled") else Ok out
    else
      let* frontend = P.Frontend.parse_input ~input_file:cfg.input_file in
      let* snapshot =
        P.Snapshot.build_snapshot ~proof_encoding:cfg.proof_encoding
          ~proof_optimizations:cfg.proof_optimizations ~frontend
          ~collect_instrumentation_info:(not (is_minimal_prove_run cfg))
          ~collect_ir_metrics:cfg.collect_ir_metrics
      in
      if is_minimal_prove_run cfg then
        match P.Outputs.build_outputs ~cfg ~snapshot with
        | Error _ as e -> e
        | Ok (out : Pipeline_types.outputs) ->
            on_outputs_ready { out with goals = [] };
            let goal_names = List.map (fun (g, _, _, _, _) -> g) out.goals in
            on_goals_ready (goal_names, out.vc_ids_ordered);
            List.iteri
              (fun i (goal, status, time_s, dump_path, vcid) ->
                on_goal_done i goal status time_s dump_path vcid)
              out.goals;
            if should_cancel () then Error (Pipeline_types.Flow_error "Request cancelled")
            else Ok out
      else
        let pending_cfg = { cfg with prove = false; compute_proof_diagnostics = false } in
        match P.Outputs.build_outputs ~cfg:pending_cfg ~snapshot with
        | Error _ as e -> e
        | Ok (pending_out : Pipeline_types.outputs) ->
            on_outputs_ready { pending_out with goals = [] };
            let goal_names = List.map (fun (g, _, _, _, _) -> g) pending_out.goals in
            on_goals_ready (goal_names, pending_out.vc_ids_ordered);
            if not cfg.prove || cfg.wp_only then Ok pending_out
            else
              let goal_results =
                P.Proof_events.prove_with_events ~timeout_s:cfg.timeout_s ~should_cancel
                  ~dump_failed_smt:cfg.dump_failed_smt ~snapshot
                  ~vc_ids_ordered:pending_out.vc_ids_ordered
                  ~on_goal_done:(fun (idx, goal, status, time_s, dump, vcid) ->
                    on_goal_done idx goal status time_s dump vcid)
              in
              if should_cancel () then Error (Pipeline_types.Flow_error "Request cancelled")
              else
                Ok
                  (Proof_diagnostics.apply_goal_results_to_outputs ~out:pending_out
                     ~goal_results)
end
