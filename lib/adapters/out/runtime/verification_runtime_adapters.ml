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

type snapshot = Runtime_snapshot.pipeline_snapshot
let ( let* ) = Result.bind

module Snapshot = struct
  type nonrec snapshot = snapshot

  let build_snapshot ~collect_instrumentation_info ~collect_ir_metrics
      ~proof_encoding ~proof_optimizations ~frontend =
    let* prepared =
      Pipeline_build.prepare_program_from_frontend ~proof_optimizations
        ~frontend
    in
    let* produced_automata =
      Runtime_automata_source.produce_with_spot prepared.reference_program
    in
    let supplied_automata : Pipeline_build.supplied_automata =
      {
        automata = produced_automata.automata;
        automata_info = produced_automata.automata_info;
      }
    in
    Pipeline_build.build_snapshot_from_supplied_automata ~proof_encoding
      ~proof_optimizations ~collect_instrumentation_info ~collect_ir_metrics
      ~prepared ~supplied_automata
end

module Outputs = struct
  type nonrec snapshot = snapshot

  let build_outputs = Pipeline_outputs.build_outputs
end

let explicit_product_optimizations (snapshot : snapshot) =
  match snapshot.proof_encoding with
  | Pipeline_types.Explicit_product -> snapshot.proof_optimizations

let instrumentation_from_snapshot ~generate_png ~(snapshot : snapshot) =
  match Pipeline_artifact_bundle.build ~asts:snapshot.asts with
  | Error msg -> Error (Pipeline_types.Flow_error msg)
  | Ok artifacts ->
      Ok
        (Output_mapper.map_automata_outputs ~generate_png ~snapshot
           ~artifacts)

module Why_text = struct
  type nonrec snapshot = snapshot

  let render_why_text ~(snapshot : snapshot) : string =
    let instrumentation =
      Runtime_ir_merge.merge_by_source
        ~source_model:snapshot.asts.verification_model
        snapshot.asts.instrumentation
    in
    let opts = explicit_product_optimizations snapshot in
    let why_ast =
      Why_compile.compile_program_ast_from_ir_nodes
        ~share_why3_facts:opts.share_why3_facts
        ~simplify_why3_formulas:opts.simplify_why3_formulas
        ~slice_why3_transition_bodies:opts.slice_why3_transition_bodies
        ~simplify_why3_runtime_actions:opts.simplify_why3_runtime_actions
        ~deduplicate_why3_terms:opts.deduplicate_why3_terms
        ~group_why3_product_steps:opts.group_why3_product_steps
        ~why3_product_step_group_max_cost:opts.why3_product_step_group_max_cost
        instrumentation
    in
    Why_text_render.emit_program_ast why_ast

  let why_text ~(snapshot : snapshot) : Pipeline_types.why_outputs =
    let why_text = render_why_text ~snapshot in
    {
      Pipeline_types.why_text;
      flow_meta =
        Pipeline_outputs.flow_meta
          ~proof_encoding:snapshot.proof_encoding
          ~proof_optimizations:snapshot.proof_optimizations snapshot.infos;
    }
end

module Cost_report = struct
  type nonrec snapshot = snapshot

  let cost_report ~input_file ~(snapshot : snapshot) :
      (Pipeline_types.cost_report_outputs, Pipeline_types.error) result =
    let t_artifacts = Unix.gettimeofday () in
    match Pipeline_artifact_bundle.build ~asts:snapshot.asts with
    | Error msg -> Error (Pipeline_types.Flow_error msg)
    | Ok artifacts ->
        let artifact_build_s = Unix.gettimeofday () -. t_artifacts in
        let t_why = Unix.gettimeofday () in
        let why_text = Why_text.render_why_text ~snapshot in
        let why_text_s = Unix.gettimeofday () -. t_why in
        Ok
          {
            Pipeline_types.cost_report_json =
              Pipeline_cost_report.render_json ~input_file ~artifact_build_s
                ~why_text_s ~snapshot ~artifacts ~why_text;
          }
end

module Obligations = struct
  type nonrec snapshot = snapshot

  let obligations ~(snapshot : snapshot) : Pipeline_types.obligations_outputs =
    let instrumentation =
      Runtime_ir_merge.merge_by_source
        ~source_model:snapshot.asts.verification_model
        snapshot.asts.instrumentation
    in
    let opts = explicit_product_optimizations snapshot in
    let out =
      Why_pipeline.obligations_pass
        ~share_why3_facts:opts.share_why3_facts
        ~simplify_why3_formulas:opts.simplify_why3_formulas
        ~slice_why3_transition_bodies:opts.slice_why3_transition_bodies
        ~simplify_why3_runtime_actions:opts.simplify_why3_runtime_actions
        ~deduplicate_why3_terms:opts.deduplicate_why3_terms
        ~group_why3_product_steps:opts.group_why3_product_steps
        ~why3_product_step_group_max_cost:opts.why3_product_step_group_max_cost
        instrumentation
    in
    { Pipeline_types.vc_text = out.vc_text; smt_text = out.smt_text }
end

module Ir_render = struct
  type nonrec snapshot = snapshot

  let normalized_program ~(snapshot : snapshot) : string =
    Ir_text_program_view_render.render_program ~source_program:(Some snapshot.asts.reference_program)
      snapshot.asts.instrumentation

  let pretty_program ~(snapshot : snapshot) : string =
    let program : Ir.program_ir = { nodes = snapshot.asts.instrumentation } in
    Ir_text_proof_view_render.render_pretty_program
      ~source_program:(Some snapshot.asts.reference_program)
      program
end

module Timing = struct
  type snapshot = External_timing.snapshot

  let now_s = Unix.gettimeofday
  let snapshot = External_timing.snapshot

  let diff ~before ~after_ : Application_ports.timing_counters =
    let d = External_timing.diff ~before ~after_ in
    let map_ir_size (size : External_timing.ir_size_metrics) :
        Application_ports.ir_size_metrics =
      {
        node_count = size.node_count;
        summary_count = size.summary_count;
        safe_case_count = size.safe_case_count;
        unsafe_case_count = size.unsafe_case_count;
        propagation_requires_count = size.propagation_requires_count;
        requires_count = size.requires_count;
        ensures_count = size.ensures_count;
        init_invariant_goal_count = size.init_invariant_goal_count;
        formula_occurrence_count = size.formula_occurrence_count;
        unique_formula_count = size.unique_formula_count;
      }
    in
    {
      frontend_parse_s = d.frontend_parse_s;
      snapshot_build_s = d.snapshot_build_s;
      contract_partition_s = d.contract_partition_s;
      automata_generation_s = d.automata_generation_s;
      spot_s = d.spot_s;
      spot_calls = d.spot_calls;
      z3_s = d.z3_s;
      z3_calls = d.z3_calls;
      product_s = d.product_s;
      canonical_s = d.canonical_s;
      pre_s = d.pre_s;
      product_reachability_s = d.product_reachability_s;
      post_s = d.post_s;
      temporal_lower_s = d.temporal_lower_s;
      instrumentation_info_s = d.instrumentation_info_s;
      output_artifact_s = d.output_artifact_s;
      output_proof_run_s = d.output_proof_run_s;
      output_map_s = d.output_map_s;
      why_gen_s = d.why_gen_s;
      vc_smt_s = d.vc_smt_s;
      why3_setup_s = d.why3_setup_s;
      why3_parse_s = d.why3_parse_s;
      why3_typecheck_s = d.why3_typecheck_s;
      why3_task_extract_s = d.why3_task_extract_s;
      why3_split_vc_s = d.why3_split_vc_s;
      why3_prepare_s = d.why3_prepare_s;
      why3_print_s = d.why3_print_s;
      why3_spawn_s = d.why3_spawn_s;
      why3_wait_s = d.why3_wait_s;
      why3_solver_s = d.why3_solver_s;
      why3_input_goal_count = d.why3_input_goal_count;
      why3_goal_count = d.why3_goal_count;
      why3_duplicate_goal_count = d.why3_duplicate_goal_count;
      why3_fallback_count = d.why3_fallback_count;
      why3_smt_fingerprint_count = d.why3_smt_fingerprint_count;
      why3_unique_smt_fingerprint_count = d.why3_unique_smt_fingerprint_count;
      why3_workers =
        List.map
          (fun (worker : External_timing.why3_worker_snapshot) ->
            {
              Application_ports.worker_id = worker.worker_id;
              worker_input_goal_count = worker.worker_input_goal_count;
              worker_prover_goal_count = worker.worker_prover_goal_count;
              worker_duplicate_goal_count = worker.worker_duplicate_goal_count;
              worker_fallback_count = worker.worker_fallback_count;
              worker_wall_s = worker.worker_wall_s;
              worker_prepare_s = worker.worker_prepare_s;
              worker_print_s = worker.worker_print_s;
              worker_spawn_s = worker.worker_spawn_s;
              worker_wait_s = worker.worker_wait_s;
              worker_solver_s = worker.worker_solver_s;
              worker_last_goal = worker.worker_last_goal;
            })
          d.why3_workers;
      ir_passes =
        List.map
          (fun (pass : External_timing.ir_pass_snapshot) ->
            {
              Application_ports.pass_name = pass.pass_name;
              before = map_ir_size pass.before;
              after_ = map_ir_size pass.after_;
            })
          d.ir_passes;
      ir_fact_families =
        List.map
          (fun (family : External_timing.ir_fact_family_snapshot) ->
            {
              Application_ports.pass_name = family.pass_name;
              family_name = family.family_name;
              candidate_count = family.candidate_count;
              inserted_count = family.inserted_count;
              unique_candidate_count = family.unique_candidate_count;
              unique_inserted_count = family.unique_inserted_count;
            })
          d.ir_fact_families;
      why3_product_groups =
        List.map
          (fun (group : External_timing.why3_product_group_snapshot) ->
            {
              Application_ports.group_name = group.group_name;
              node_name = group.node_name;
              transition_id = group.transition_id;
              step_class = group.step_class;
              source_state = group.source_state;
              emitted_as_group = group.emitted_as_group;
              split_due_to_cost = group.split_due_to_cost;
              edge_count = group.edge_count;
              distinct_pre_count = group.distinct_pre_count;
              distinct_post_count = group.distinct_post_count;
              post_implication_count = group.post_implication_count;
              pre_text_bytes = group.pre_text_bytes;
              post_text_bytes = group.post_text_bytes;
              estimated_cost = group.estimated_cost;
              max_cost = group.max_cost;
            })
          d.why3_product_groups;
    }

  let record_frontend_parse = External_timing.record_frontend_parse
  let record_snapshot_build = External_timing.record_snapshot_build
end

module Proof_events = struct
  type nonrec snapshot = snapshot

  let prove_with_events ~timeout_s ~dump_failed_smt ~should_cancel ~(snapshot : snapshot)
      ~(vc_ids_ordered : int list) ~on_goal_done : Application_ports.goal_result list =
    let instrumentation =
      Runtime_ir_merge.merge_by_source
        ~source_model:snapshot.asts.verification_model
        snapshot.asts.instrumentation
    in
    let opts = explicit_product_optimizations snapshot in
    let ptree =
      (Why_compile.compile_program_ast_from_ir_nodes
         ~share_why3_facts:opts.share_why3_facts
         ~simplify_why3_formulas:opts.simplify_why3_formulas
         ~slice_why3_transition_bodies:opts.slice_why3_transition_bodies
         ~simplify_why3_runtime_actions:opts.simplify_why3_runtime_actions
         ~deduplicate_why3_terms:opts.deduplicate_why3_terms
         ~group_why3_product_steps:opts.group_why3_product_steps
         ~why3_product_step_group_max_cost:opts.why3_product_step_group_max_cost
         instrumentation)
        .Why_compile.mlw
    in
    let finished = ref [] in
    let _ =
      Why_contract_prove.prove_ptree_with_events ~timeout:timeout_s ptree ~should_cancel
        ~dump_failed_smt ~on_goal_start:(fun _ -> ()) ~on_goal_done:(fun ev ->
          let idx = ev.goal_index in
          let r = ev.result in
          let status = Proof_status_render.of_prover_answer r.prover_result.pr_answer in
          let vcid =
            match List.nth_opt vc_ids_ordered idx with
            | Some id -> Some (string_of_int id)
            | None -> None
          in
          let item = (idx, r.goal_name, status, r.prover_result.pr_time, r.dump_path, vcid) in
          finished := item :: !finished;
          on_goal_done item)
    in
    List.sort (fun (a, _, _, _, _, _) (b, _, _, _, _, _) -> Int.compare a b) !finished
end
