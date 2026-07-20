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

  module Timing_meta = Verification_flow_timing_meta.Make (P)

  let is_minimal_prove_run (cfg : Pipeline_types.config) : bool =
    cfg.prove && not cfg.wp_only && not cfg.compute_proof_diagnostics
    && not cfg.generate_vc_text && not cfg.generate_smt_text
    && not cfg.generate_dot_png && Option.is_none cfg.proof_progress_path

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
        ~collect_instrumentation_info:
          ((not (is_minimal_prove_run cfg)) || cfg.collect_ir_metrics)
        ~collect_ir_metrics:cfg.collect_ir_metrics
    in
    P.Timing.record_snapshot_build
      ~elapsed_s:(P.Timing.now_s () -. t_snapshot);
    let t_build_done = P.Timing.now_s () in
    match P.Outputs.build_outputs ~cfg ~snapshot with
    | Error _ as e -> e
    | Ok out ->
        Ok
          (Timing_meta.with_timing_flow_meta ~t0 ~t_build_done ~snap_before out)

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
    match P.Outputs.build_outputs ~cfg ~snapshot with
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
    match P.Outputs.build_outputs ~cfg:pending_cfg ~snapshot with
    | Error _ as e -> e
    | Ok (pending_out : Pipeline_types.outputs) ->
        emit_goal_callbacks ~on_outputs_ready ~on_goals_ready ~on_goal_done
          pending_out;
        if not cfg.prove || cfg.wp_only then Ok pending_out
        else
          let goal_results =
            P.Proof_events.prove_with_events ~timeout_s:cfg.timeout_s
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
      let* frontend = P.Frontend.parse_input ~input_file:cfg.input_file in
      let* snapshot =
        P.Snapshot.build_snapshot ~proof_encoding:cfg.proof_encoding
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
end
