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
let ( let* ) = Result.bind

let error_of_frontend = function
  | Kairos_frontend.Parse_error message -> Pipeline_types.Parse_error message
  | Kairos_frontend.Elaboration_error message ->
      Pipeline_types.Elaboration_error message
  | Kairos_frontend.Type_error message -> Pipeline_types.Type_error message
  | Kairos_frontend.Well_formedness_error message ->
      Pipeline_types.Well_formedness_error message
  | Kairos_frontend.Io_error message -> Pipeline_types.Io_error message
  | Kairos_frontend.Internal_error message ->
      Pipeline_types.Internal_error message

let flow_parse_info (info : Kairos_frontend.parse_info) : Flow_info.parse_info =
  {
    source_path = info.source_path;
    text_hash = info.text_hash;
    parse_errors =
      List.map
        (fun (error : Kairos_frontend.parse_error) ->
          ({ loc = error.loc; message = error.message } : Flow_info.parse_error))
        info.parse_errors;
    warnings = info.warnings;
  }

let parse_input ~input_file =
  Kairos_frontend.parse_input ~input_file |> Result.map_error error_of_frontend

let () =
  Why_adapter_log.set_handlers
    ~progress:(fun message -> Log.flow_info (Some "prove") message [])
    ~warning:(fun message -> Log.warning ~stage:"prove" message)

type snapshot = Runtime_snapshot.pipeline_snapshot

let build_snapshot ~collect_instrumentation_info ~collect_ir_metrics
    ~proof_encoding ~proof_optimizations
    ~(frontend : Kairos_frontend.input) =
  let* prepared =
    Pipeline_build.prepare_program ~proof_optimizations
      ~imports:frontend.imports
      ~parse_info:(flow_parse_info frontend.parse_info)
      ~verification_model:frontend.verification_model
  in
  let* produced_automata =
    Runtime_automata_source.produce_with_spot prepared.reference_program
  in
  Pipeline_build.build_snapshot_from_supplied_automata ~proof_encoding
    ~proof_optimizations ~collect_instrumentation_info ~collect_ir_metrics
    ~prepared ~automata:produced_automata.automata
    ~automata_info:produced_automata.automata_info

let build_outputs = Pipeline_outputs.build_outputs

let explicit_product_optimizations (snapshot : snapshot) =
  match snapshot.proof_encoding with
  | Pipeline_types.Explicit_product -> snapshot.proof_optimizations

let why_compilation_options (opts : Pipeline_types.proof_optimizations) :
    Why_pipeline.compilation_options =
  {
    group_product_steps = opts.group_why3_product_steps;
  }

let instrumentation_from_snapshot ~generate_png ~(snapshot : snapshot) =
  match Pipeline_artifact_bundle.build ~asts:snapshot.asts with
  | Error msg -> Error (Pipeline_types.Flow_error msg)
  | Ok artifacts ->
      Ok
        (Output_mapper.map_automata_outputs ~generate_png ~snapshot
           ~artifacts)

let merged_instrumentation (snapshot : snapshot) =
  snapshot.asts.proof_backend_nodes

let render_why_text ~(snapshot : snapshot) : string =
  let instrumentation = merged_instrumentation snapshot in
  let opts = explicit_product_optimizations snapshot in
  Why_pipeline.compile_whyml ~nodes:instrumentation
    ~step_projections:snapshot.asts.step_projections
    ~options:(why_compilation_options opts) ()
  |> fun output -> output.Why_pipeline.text

let why_text ~(snapshot : snapshot) : Pipeline_types.why_outputs =
  {
    Pipeline_types.why_text = render_why_text ~snapshot;
    flow_meta =
      Pipeline_outputs.flow_meta
        ~proof_encoding:snapshot.proof_encoding
        ~proof_optimizations:snapshot.proof_optimizations snapshot.infos;
  }

let cost_report_from_snapshot ~input_file ~(snapshot : snapshot) :
    (Pipeline_types.cost_report_outputs, Pipeline_types.error) result =
  let t_artifacts = Unix.gettimeofday () in
  match Pipeline_artifact_bundle.build ~asts:snapshot.asts with
  | Error msg -> Error (Pipeline_types.Flow_error msg)
  | Ok artifacts ->
      let artifact_build_s = Unix.gettimeofday () -. t_artifacts in
      let t_why = Unix.gettimeofday () in
      let why_text = render_why_text ~snapshot in
      let why_text_s = Unix.gettimeofday () -. t_why in
      Ok
        {
          Pipeline_types.cost_report_json =
            Pipeline_cost_report.render_json ~input_file ~artifact_build_s
              ~why_text_s ~snapshot ~artifacts ~why_text;
        }

let obligations ~(snapshot : snapshot) :
    Pipeline_types.obligations_outputs =
  let instrumentation = merged_instrumentation snapshot in
  let opts = explicit_product_optimizations snapshot in
  let out =
    Why_pipeline.obligations_pass ~nodes:instrumentation
      ~step_projections:snapshot.asts.step_projections
      ~options:(why_compilation_options opts)
  in
  { Pipeline_types.vc_text = out.vc_text; smt_text = out.smt_text }

let normalized_program_from_snapshot ~(snapshot : snapshot) : string =
  Ir_text_program_view_render.render_program
    ~source_program:(Some snapshot.asts.reference_program)
    snapshot.asts.instrumentation

let pretty_program_from_snapshot ~(snapshot : snapshot) : string =
  let program : Ir.program_ir = { nodes = snapshot.asts.instrumentation } in
  Ir_text_proof_view_render.render_pretty_program
    ~source_program:(Some snapshot.asts.reference_program)
    program

let prove_with_events ~timeout_s ~dump_failed_smt ~should_cancel
    ~(snapshot : snapshot) ~(vc_ids_ordered : int list) ~on_goal_done :
    Pipeline_types.goal_result list =
  let whyml_text = render_why_text ~snapshot in
  let module Contract = Kairos_proof_contract.Proof_backend_contract in
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
  let request = Contract.make_execution_request ~whyml_text ~options () in
  let finished = ref [] in
  let _ =
    Why_execution.execute ~should_cancel ~on_goal_start:(fun _ -> ())
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
      request
  in
  List.sort
    (fun (a, _, _, _, _, _) (b, _, _, _, _, _) -> Int.compare a b)
    !finished

  let is_minimal_prove_run (cfg : Pipeline_types.config) : bool =
    cfg.prove && not cfg.wp_only && not cfg.compute_proof_diagnostics
    && not cfg.generate_vc_text && not cfg.generate_smt_text
    && not cfg.generate_dot_png && Option.is_none cfg.proof_progress_path

let instrumentation_pass ~generate_png ~input_file =
  let* frontend = parse_input ~input_file in
  let* snapshot =
    build_snapshot
      ~proof_encoding:Pipeline_types.default_proof_encoding
      ~proof_optimizations:Pipeline_types.default_proof_optimizations ~frontend
      ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  instrumentation_from_snapshot ~generate_png ~snapshot

let why_pass ~proof_encoding ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* snapshot =
    build_snapshot ~proof_encoding ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok (why_text ~snapshot)

let obligations_pass ~proof_encoding ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* snapshot =
    build_snapshot ~proof_encoding ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok (obligations ~snapshot)

let cost_report ~proof_encoding ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* snapshot =
    build_snapshot ~proof_encoding ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  cost_report_from_snapshot ~input_file ~snapshot

let normalized_program ~proof_encoding ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* snapshot =
    build_snapshot ~proof_encoding ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok (normalized_program_from_snapshot ~snapshot)

let ir_pretty_dump ~proof_encoding ~proof_optimizations ~input_file =
  let* frontend = parse_input ~input_file in
  let* snapshot =
    build_snapshot ~proof_encoding ~proof_optimizations
      ~frontend ~collect_instrumentation_info:true ~collect_ir_metrics:false
  in
  Ok (pretty_program_from_snapshot ~snapshot)

let run (cfg : Pipeline_types.config) =
  let t0 = Unix.gettimeofday () in
  let snap_before = External_timing.snapshot () in
  let t_parse = Unix.gettimeofday () in
  let* frontend = parse_input ~input_file:cfg.input_file in
  External_timing.record_frontend_parse
    ~elapsed_s:(Unix.gettimeofday () -. t_parse);
  let t_snapshot = Unix.gettimeofday () in
  let* snapshot =
    build_snapshot
      ~proof_encoding:cfg.proof_encoding
      ~proof_optimizations:cfg.proof_optimizations ~frontend
      ~collect_instrumentation_info:
        ((not (is_minimal_prove_run cfg)) || cfg.collect_ir_metrics)
      ~collect_ir_metrics:cfg.collect_ir_metrics
  in
  External_timing.record_snapshot_build
    ~elapsed_s:(Unix.gettimeofday () -. t_snapshot);
  let t_build_done = Unix.gettimeofday () in
  match build_outputs ~cfg ~snapshot with
  | Error _ as e -> e
  | Ok out ->
      Ok
        (Engine_timing_meta.with_timing_flow_meta ~t0 ~t_build_done
           ~snap_before out)

  let emit_goal_callbacks ?vc_ids_ordered ~on_outputs_ready ~on_goals_ready
      ~on_goal_done (out : Pipeline_types.outputs) =
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

  let run_diagnostics_with_callbacks ~should_cancel (cfg : Pipeline_types.config)
      ~on_outputs_ready ~on_goals_ready ~on_goal_done =
    match run cfg with
    | Error _ as e -> e
    | Ok (out : Pipeline_types.outputs) ->
        let vc_ids_ordered = List.init (List.length out.goals) (fun i -> i + 1) in
        emit_goal_callbacks ~vc_ids_ordered ~on_outputs_ready ~on_goals_ready
          ~on_goal_done out;
        if should_cancel () then Error (Pipeline_types.Flow_error "Request cancelled")
        else Ok out

  let run_minimal_prove_with_callbacks ~should_cancel
      (cfg : Pipeline_types.config) snapshot ~on_outputs_ready ~on_goals_ready
      ~on_goal_done =
    match build_outputs ~cfg ~snapshot with
    | Error _ as e -> e
    | Ok (out : Pipeline_types.outputs) ->
        emit_goal_callbacks ~on_outputs_ready ~on_goals_ready ~on_goal_done out;
        if should_cancel () then Error (Pipeline_types.Flow_error "Request cancelled")
        else Ok out

  let run_progressive_prove_with_callbacks ~should_cancel
      (cfg : Pipeline_types.config) snapshot ~on_outputs_ready ~on_goals_ready
      ~on_goal_done =
    let pending_cfg =
      { cfg with prove = false; compute_proof_diagnostics = false }
    in
    match build_outputs ~cfg:pending_cfg ~snapshot with
    | Error _ as e -> e
    | Ok (pending_out : Pipeline_types.outputs) ->
        emit_goal_callbacks ~on_outputs_ready ~on_goals_ready ~on_goal_done
          pending_out;
        if not cfg.prove || cfg.wp_only then Ok pending_out
        else
          let goal_results =
            prove_with_events
              ~timeout_s:cfg.timeout_s
              ~should_cancel ~dump_failed_smt:cfg.dump_failed_smt ~snapshot
              ~vc_ids_ordered:pending_out.vc_ids_ordered
              ~on_goal_done:(fun (idx, goal, status, time_s, dump, vcid) ->
                on_goal_done idx goal status time_s dump vcid)
          in
          if should_cancel () then
            Error (Pipeline_types.Flow_error "Request cancelled")
          else
            Ok
              (Proof_diagnostics.apply_goal_results_to_outputs ~out:pending_out
                 ~goal_results)

  let run_with_callbacks ~should_cancel (cfg : Pipeline_types.config)
      ~on_outputs_ready ~on_goals_ready ~on_goal_done =
    if cfg.compute_proof_diagnostics then
      run_diagnostics_with_callbacks ~should_cancel cfg ~on_outputs_ready
        ~on_goals_ready ~on_goal_done
    else
      let* frontend = parse_input ~input_file:cfg.input_file in
      let* snapshot =
        build_snapshot
          ~proof_encoding:cfg.proof_encoding
          ~proof_optimizations:cfg.proof_optimizations ~frontend
          ~collect_instrumentation_info:
            ((not (is_minimal_prove_run cfg)) || cfg.collect_ir_metrics)
          ~collect_ir_metrics:cfg.collect_ir_metrics
      in
      if is_minimal_prove_run cfg then
        run_minimal_prove_with_callbacks ~should_cancel cfg snapshot
          ~on_outputs_ready ~on_goals_ready ~on_goal_done
      else
        run_progressive_prove_with_callbacks ~should_cancel cfg snapshot
          ~on_outputs_ready ~on_goals_ready ~on_goal_done
