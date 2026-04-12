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
  let fmt_s x = Printf.sprintf "%.6f" x

  let solver_sum_s (goals : Pipeline_types.goal_info list) : float =
    List.fold_left (fun acc (_, _, time_s, _, _) -> acc +. time_s) 0.0 goals

  let with_timing_flow_meta ~(t0 : float) ~(t_build_done : float)
      ~(snap_before : P.Timing.snapshot) (out : Pipeline_types.outputs) : Pipeline_types.outputs =
    let t_end = Unix.gettimeofday () in
    let counters = P.Timing.diff ~before:snap_before ~after_:(P.Timing.snapshot ()) in
    let solver_s = solver_sum_s out.goals in
    let timing_fields =
      [
        ("total_wall_s", fmt_s (t_end -. t0));
        ("build_ast_s", fmt_s (t_build_done -. t0));
        ("build_outputs_s", fmt_s (t_end -. t_build_done));
        ("spot_s", fmt_s counters.spot_s);
        ("spot_calls", string_of_int counters.spot_calls);
        ("z3_s", fmt_s counters.z3_s);
        ("z3_calls", string_of_int counters.z3_calls);
        ("product_s", fmt_s counters.product_s);
        ("canonical_s", fmt_s counters.canonical_s);
        ("why_gen_s", fmt_s counters.why_gen_s);
        ("vc_smt_s", fmt_s counters.vc_smt_s);
        ("solver_sum_s", fmt_s solver_s);
        ("solver_goal_count", string_of_int (List.length out.goals));
      ]
    in
    { out with flow_meta = out.flow_meta @ [ ("timings", timing_fields) ] }

  let instrumentation_pass = P.Instrumentation.instrumentation_pass

  let why_pass ~input_file =
    match P.Snapshot.build_snapshot ~input_file with
    | Error _ as e -> e
    | Ok snapshot -> Ok (P.Why_text.why_text ~snapshot)

  let obligations_pass ~input_file =
    match P.Snapshot.build_snapshot ~input_file with
    | Error _ as e -> e
    | Ok snapshot -> Ok (P.Obligations.obligations ~snapshot)

  let normalized_program ~input_file =
    match P.Snapshot.build_snapshot ~input_file with
    | Error _ as err -> err
    | Ok snapshot -> Ok (P.Ir_render.normalized_program ~snapshot)

  let ir_pretty_dump ~input_file =
    match P.Snapshot.build_snapshot ~input_file with
    | Error _ as err -> err
    | Ok snapshot -> Ok (P.Ir_render.pretty_program ~snapshot)

  let run (cfg : Pipeline_types.config) =
    let t0 = Unix.gettimeofday () in
    let snap_before = P.Timing.snapshot () in
    match P.Snapshot.build_snapshot ~input_file:cfg.input_file with
    | Error _ as e -> e
    | Ok snapshot ->
        let t_build_done = Unix.gettimeofday () in
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
      match P.Snapshot.build_snapshot ~input_file:cfg.input_file with
      | Error _ as e -> e
      | Ok snapshot ->
          let pending_cfg = { cfg with prove = false; compute_proof_diagnostics = false } in
          (match P.Outputs.build_outputs ~cfg:pending_cfg ~snapshot with
          | Error _ as e -> e
          | Ok (pending_out : Pipeline_types.outputs) ->
              on_outputs_ready { pending_out with goals = [] };
              let goal_names = List.map (fun (g, _, _, _, _) -> g) pending_out.goals in
              on_goals_ready (goal_names, pending_out.vc_ids_ordered);
              if not cfg.prove || cfg.wp_only then Ok pending_out
              else
                let goal_results =
                  P.Proof_events.prove_with_events ~timeout_s:cfg.timeout_s ~should_cancel ~snapshot
                    ~vc_ids_ordered:pending_out.vc_ids_ordered ~on_goal_done:(fun (idx, goal, status, time_s, dump, vcid) ->
                      on_goal_done idx goal status time_s dump vcid)
                in
                if should_cancel () then Error (Pipeline_types.Flow_error "Request cancelled")
                else
                  Ok
                    (Proof_diagnostics.apply_goal_results_to_outputs ~out:pending_out
                       ~goal_results))
end
