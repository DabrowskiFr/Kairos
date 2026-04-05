(** High-level orchestration for full compilation/proof runs. *)

let fmt_s x = Printf.sprintf "%.6f" x

let solver_sum_s (goals : Pipeline_types.goal_info list) : float =
  List.fold_left (fun acc (_, _, time_s, _, _, _) -> acc +. time_s) 0.0 goals

let with_timing_stage_meta ~(t0 : float) ~(t_build_done : float)
    ~(snap_before : External_timing.snapshot) (out : Pipeline_types.outputs) :
    Pipeline_types.outputs =
  let t_end = Unix.gettimeofday () in
  let counters = External_timing.diff ~before:snap_before ~after_:(External_timing.snapshot ()) in
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
  { out with stage_meta = out.stage_meta @ [ ("timings", timing_fields) ] }

let run ~build_ast_with_info ~build_outputs (cfg : Pipeline_types.config) =
  let t0 = Unix.gettimeofday () in
  let snap_before = External_timing.snapshot () in
  match build_ast_with_info ~input_file:cfg.input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let t_build_done = Unix.gettimeofday () in
      (match build_outputs ~cfg ~asts ~infos with
      | Error _ as e -> e
      | Ok out -> Ok (with_timing_stage_meta ~t0 ~t_build_done ~snap_before out))

let run_with_callbacks ~build_ast_with_info ~build_outputs ~should_cancel
    (cfg : Pipeline_types.config) ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  if cfg.compute_proof_diagnostics then
    match run ~build_ast_with_info ~build_outputs cfg with
    | Error _ as e -> e
    | Ok (out : Pipeline_types.outputs) ->
        on_outputs_ready { out with goals = [] };
        let goal_names = List.map (fun (g, _, _, _, _, _) -> g) out.goals in
        let vc_ids = List.init (List.length out.goals) (fun i -> i + 1) in
        on_goals_ready (goal_names, vc_ids);
        List.iteri
          (fun i (goal, status, time_s, dump_path, source, vcid) ->
            on_goal_done i goal status time_s dump_path source vcid)
          out.goals;
        if should_cancel () then Error (Pipeline_types.Stage_error "Request cancelled") else Ok out
  else
    match build_ast_with_info ~input_file:cfg.input_file () with
    | Error _ as e -> e
    | Ok (asts, infos) ->
        let pending_cfg = { cfg with prove = false; compute_proof_diagnostics = false } in
        (match build_outputs ~cfg:pending_cfg ~asts ~infos with
        | Error _ as e -> e
        | Ok (pending_out : Pipeline_types.outputs) ->
            on_outputs_ready { pending_out with goals = [] };
            let goal_names = List.map (fun (g, _, _, _, _, _) -> g) pending_out.goals in
            on_goals_ready (goal_names, pending_out.vc_ids_ordered);
            if not cfg.prove || cfg.wp_only then Ok pending_out
            else
              let finished = ref [] in
              let _summary, _ =
                Why_contract_prove.prove_text_detailed_with_callbacks ~timeout:cfg.timeout_s
                  ~prover:cfg.prover ?prover_cmd:cfg.prover_cmd
                  ?selected_goal_index:cfg.selected_goal_index ~text:pending_out.why_text
                  ~vc_ids_ordered:(Some pending_out.vc_ids_ordered)
                  ~should_cancel ~on_goal_start:(fun _ _ -> ())
                  ~on_goal_done:(fun idx goal status time_s dump_path source vcid ->
                    finished := (idx, goal, status, time_s, dump_path, source, vcid) :: !finished;
                    on_goal_done idx goal status time_s dump_path source vcid)
                  ()
              in
              if should_cancel () then Error (Pipeline_types.Stage_error "Request cancelled")
              else
                let goal_results =
                  List.sort
                    (fun (a, _, _, _, _, _, _) (b, _, _, _, _, _, _) -> compare a b)
                    !finished
                in
                Ok
                  (Proof_diagnostics.apply_goal_results_to_outputs ~out:pending_out
                     ~goal_results))
