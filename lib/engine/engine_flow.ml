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

(** Concrete orchestration of the Kairos engine. *)
module Frontend = Kairos_input_lang.Kairos_frontend

let ( let* ) = Result.bind

let error_of_frontend = function
  | Frontend.Parse_error message -> Pipeline_error.Parse_error message
  | Frontend.Elaboration_error message ->
      Pipeline_error.Elaboration_error message
  | Frontend.Type_error message -> Pipeline_error.Type_error message
  | Frontend.Well_formedness_error message ->
      Pipeline_error.Well_formedness_error message
  | Frontend.Io_error message -> Pipeline_error.Io_error message
  | Frontend.Internal_error message ->
      Pipeline_error.Internal_error message

let flow_parse_info (info : Frontend.parse_info) : Flow_info.parse_info =
  {
    source_path = info.source_path;
    text_hash = info.text_hash;
    parse_errors = [];
    warnings = info.warnings;
  }

let parse_input ~input_file =
  Frontend.parse_input ~input_file |> Result.map_error error_of_frontend

let () =
  Why_adapter_log.set_handlers
    ~progress:(fun message -> Log.flow_info (Some "prove") message [])
    ~warning:(fun message -> Log.warning ~stage:"prove" message)

let build_pipeline ~collect_instrumentation_info ~collect_ir_metrics
    ~proof_optimizations
    ~(frontend : Frontend.output) =
  let* prepared =
    Pipeline_build.prepare_program ~proof_optimizations
      ~parse_info:(flow_parse_info frontend.parse_info)
      ~verification_model:frontend.verification_model
  in
  let* produced_automata =
    Runtime_automata_source.produce_with_spot prepared.proof_case_program
  in
  Pipeline_build.build_from_supplied_automata
    ~proof_optimizations ~collect_instrumentation_info ~collect_ir_metrics
    ~prepared ~automata:produced_automata.automata
    ~automata_info:produced_automata.automata_info

let proof_cases (pipeline : Pipeline_build.build_result) =
  pipeline.verification.proof_cases

let product_nodes (pipeline : Pipeline_build.build_result) =
  pipeline.verification.reference_product.nodes

let instrumentation (pipeline : Pipeline_build.build_result) =
  List.map
    (fun
      (node : Orchestration.instrumented_product_node)
    ->
      node.ir)
    pipeline.verification.instrumented_nodes

let build_outputs ~cfg (pipeline : Pipeline_build.build_result) =
  Pipeline_outputs.build_outputs ~cfg
    ~proof_cases:(proof_cases pipeline)
    ~product_nodes:(product_nodes pipeline)
    ~proof_plans:pipeline.proof_plans ~infos:pipeline.infos

let instrumentation_from_pipeline ~generate_png ~proof_optimizations
    (pipeline : Pipeline_build.build_result) =
  let artifacts =
    Pipeline_artifact_bundle.build
      ~product_nodes:(product_nodes pipeline)
  in
  Ok
    (Output_mapper.map_automata_outputs ~generate_png
       ~proof_optimizations
       ~proof_cases:(proof_cases pipeline) ~infos:pipeline.infos
       ~artifacts)

let render_why_text ~proof_plans : string =
  Why_pipeline.compile ~proof_plans ()
  |> Why_pipeline.render
  |> fun output -> output.Why_pipeline.text

let why_text ~proof_optimizations ~infos
    ~proof_plans : Pipeline_artifacts.why_outputs =
  {
    Pipeline_artifacts.why_text = render_why_text ~proof_plans;
    flow_meta =
      Pipeline_outputs.flow_meta
        ~proof_optimizations infos;
  }

let cost_report_from_pipeline ~input_file ~proof_optimizations
    (pipeline : Pipeline_build.build_result) :
    (Pipeline_artifacts.cost_report_outputs, Pipeline_error.t) result =
  let t_why = Unix.gettimeofday () in
  let why_text =
    render_why_text ~proof_plans:pipeline.proof_plans
  in
  let why_text_s = Unix.gettimeofday () -. t_why in
  Ok
    {
      Pipeline_artifacts.cost_report_json =
        Pipeline_cost_report.render_json ~input_file ~why_text_s
          ~proof_optimizations
          ~infos:pipeline.infos
          ~proof_cases:(proof_cases pipeline)
          ~instrumentation:(instrumentation pipeline) ~why_text;
    }

let obligations ~proof_plans :
    Pipeline_artifacts.obligations_outputs =
  let out =
    Why_pipeline.obligations_pass ~proof_plans
  in
  Runtime_metrics.record_why3_execution out.metrics;
  { Pipeline_artifacts.vc_text = out.vc_text; smt_text = out.smt_text }

let normalized_program_from_pipeline
    (pipeline : Pipeline_build.build_result) : string =
  let source_program =
    Proof_case_program.program (proof_cases pipeline)
  in
  Ir_text_program_view_render.render_program
    ~source_program:(Some source_program)
    (instrumentation pipeline)

let pretty_program_from_pipeline
    (pipeline : Pipeline_build.build_result) : string =
  let source_program =
    Proof_case_program.program (proof_cases pipeline)
  in
  let program : Ir.program_ir =
    { nodes = instrumentation pipeline }
  in
  Ir_text_proof_view_render.render_pretty_program
    ~source_program:(Some source_program)
    program

let prove_with_events ~timeout_s ~dump_failed_smt ~should_cancel
    ~proof_plans ~(vc_ids_ordered : int list) ~on_goal_done :
    Pipeline_proof_types.goal_result list =
  let compilation = Why_pipeline.compile ~proof_plans () in
  let module Contract = Kairos_why3_contract.Why3_contract in
  let options : Contract.execution_options =
    {
      timeout_s;
      jobs = 1;
      split_vc = true;
      dump_failed_smt;
      prove = true;
      emit_vc_text = false;
      emit_smt_text = false;
      diagnose_nonvalid = false;
    }
  in
  let finished = ref [] in
  let response =
    Why_execution.execute_ptree ~should_cancel
      ~on_goal_start:(fun _ -> ())
      ~on_goal_done:(fun result ->
        let idx = result.Contract.goal_index in
        let status = Contract.string_of_proof_status result.status in
        let vcid =
          match List.nth_opt vc_ids_ordered idx with
          | Some id -> Some (string_of_int id)
          | None -> None
        in
        let item =
          ( idx,
            result.goal_name,
            status,
            result.prover_time_s,
            result.dump_path,
            vcid )
        in
        finished := item :: !finished;
        on_goal_done item)
      ~options compilation.ast
  in
  Runtime_metrics.record_why3_execution response.metrics;
  List.sort
    (fun (a, _, _, _, _, _) (b, _, _, _, _, _) -> Int.compare a b)
    !finished

  let is_minimal_prove_run (cfg : Pipeline_config.config) : bool =
    cfg.prove && not cfg.wp_only && not cfg.compute_proof_diagnostics
    && not cfg.generate_vc_text && not cfg.generate_smt_text
    && not cfg.generate_dot_png && Option.is_none cfg.proof_progress_path

let instrumentation_pass ~generate_png ~input_file =
  let* frontend = parse_input ~input_file in
  let proof_optimizations =
    Pipeline_config.default_proof_optimizations
  in
  let* pipeline =
    build_pipeline
      ~proof_optimizations ~frontend
      ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  instrumentation_from_pipeline ~generate_png ~proof_optimizations
    pipeline

let why_pass ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* pipeline =
    build_pipeline ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok
    (why_text ~proof_optimizations
       ~infos:pipeline.infos ~proof_plans:pipeline.proof_plans)

let obligations_pass ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* pipeline =
    build_pipeline ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok (obligations ~proof_plans:pipeline.proof_plans)

let cost_report ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* pipeline =
    build_pipeline ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  cost_report_from_pipeline ~input_file ~proof_optimizations
    pipeline

let normalized_program ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* pipeline =
    build_pipeline ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok (normalized_program_from_pipeline pipeline)

let ir_pretty_dump ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* pipeline =
    build_pipeline ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok (pretty_program_from_pipeline pipeline)

let run (cfg : Pipeline_config.config) =
  let t0 = Unix.gettimeofday () in
  let snap_before = Runtime_metrics.snapshot () in
  let t_parse = Unix.gettimeofday () in
  let* frontend = parse_input ~input_file:cfg.input_file in
  Runtime_metrics.record_frontend_parse
    ~elapsed_s:(Unix.gettimeofday () -. t_parse);
  let t_pipeline = Unix.gettimeofday () in
  let* pipeline =
    build_pipeline
      ~proof_optimizations:cfg.proof_optimizations ~frontend
      ~collect_instrumentation_info:
        ((not (is_minimal_prove_run cfg)) || cfg.collect_ir_metrics)
      ~collect_ir_metrics:cfg.collect_ir_metrics
  in
  Runtime_metrics.record_pipeline_build
    ~elapsed_s:(Unix.gettimeofday () -. t_pipeline);
  let t_build_done = Unix.gettimeofday () in
  match build_outputs ~cfg pipeline with
  | Error _ as e -> e
  | Ok out ->
      Ok
        (Engine_timing_meta.with_timing_flow_meta ~t0 ~t_build_done
           ~snap_before out)

  let emit_goal_callbacks ?vc_ids_ordered ~on_outputs_ready ~on_goals_ready
      ~on_goal_done (out : Pipeline_artifacts.outputs) =
    on_outputs_ready { out with goals = [] };
    let goal_names = List.map (fun (g, _, _, _, _) -> g) out.goals in
    let vc_ids_ordered =
      Option.value ~default:out.vc_ids_ordered vc_ids_ordered
    in
    on_goals_ready (goal_names, vc_ids_ordered);
    List.iteri
      (fun i (goal, status, time_s, dump_path, vcid) ->
        on_goal_done i goal status time_s dump_path vcid)
      out.goals

  let run_diagnostics_with_callbacks ~should_cancel (cfg : Pipeline_config.config)
      ~on_outputs_ready ~on_goals_ready ~on_goal_done =
    match run cfg with
    | Error _ as e -> e
    | Ok (out : Pipeline_artifacts.outputs) ->
        let vc_ids_ordered = List.init (List.length out.goals) (fun i -> i + 1) in
        emit_goal_callbacks ~vc_ids_ordered ~on_outputs_ready ~on_goals_ready
          ~on_goal_done out;
        if should_cancel () then Error (Pipeline_error.Flow_error "Request cancelled")
        else Ok out

  let run_minimal_prove_with_callbacks ~should_cancel
      (cfg : Pipeline_config.config) pipeline ~on_outputs_ready ~on_goals_ready
      ~on_goal_done =
    match build_outputs ~cfg pipeline with
    | Error _ as e -> e
    | Ok (out : Pipeline_artifacts.outputs) ->
        emit_goal_callbacks ~on_outputs_ready ~on_goals_ready ~on_goal_done out;
        if should_cancel () then Error (Pipeline_error.Flow_error "Request cancelled")
        else Ok out

  let run_progressive_prove_with_callbacks ~should_cancel
      (cfg : Pipeline_config.config) pipeline ~on_outputs_ready ~on_goals_ready
      ~on_goal_done =
    let pending_cfg =
      { cfg with prove = false; compute_proof_diagnostics = false }
    in
    match build_outputs ~cfg:pending_cfg pipeline with
    | Error _ as e -> e
    | Ok (pending_out : Pipeline_artifacts.outputs) ->
        emit_goal_callbacks ~on_outputs_ready ~on_goals_ready ~on_goal_done
          pending_out;
        if not cfg.prove || cfg.wp_only then Ok pending_out
        else
          let goal_results =
            prove_with_events
              ~timeout_s:cfg.timeout_s
              ~should_cancel ~dump_failed_smt:cfg.dump_failed_smt
              ~proof_plans:pipeline.proof_plans
              ~vc_ids_ordered:pending_out.vc_ids_ordered
              ~on_goal_done:(fun (idx, goal, status, time_s, dump, vcid) ->
                on_goal_done idx goal status time_s dump vcid)
          in
          if should_cancel () then
            Error (Pipeline_error.Flow_error "Request cancelled")
          else
            Ok
              (Proof_diagnostics.apply_goal_results_to_outputs ~out:pending_out
                 ~goal_results)

  let run_with_callbacks ~should_cancel (cfg : Pipeline_config.config)
      ~on_outputs_ready ~on_goals_ready ~on_goal_done =
    if cfg.compute_proof_diagnostics then
      run_diagnostics_with_callbacks ~should_cancel cfg ~on_outputs_ready
        ~on_goals_ready ~on_goal_done
    else
      let* frontend = parse_input ~input_file:cfg.input_file in
      let* pipeline =
        build_pipeline
          ~proof_optimizations:cfg.proof_optimizations ~frontend
          ~collect_instrumentation_info:
            ((not (is_minimal_prove_run cfg)) || cfg.collect_ir_metrics)
          ~collect_ir_metrics:cfg.collect_ir_metrics
      in
      if is_minimal_prove_run cfg then
        run_minimal_prove_with_callbacks ~should_cancel cfg pipeline
          ~on_outputs_ready ~on_goals_ready ~on_goal_done
      else
        run_progressive_prove_with_callbacks ~should_cancel cfg pipeline
          ~on_outputs_ready ~on_goals_ready ~on_goal_done
