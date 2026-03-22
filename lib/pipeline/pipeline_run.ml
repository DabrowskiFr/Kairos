(** High-level run orchestration shared by the v2 pipeline implementation. *)

let run ~build_ast_with_info ~build_outputs (cfg : Pipeline.config) =
  match build_ast_with_info ~input_file:cfg.input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) -> build_outputs ~cfg ~asts ~infos

let run_with_callbacks ~build_ast_with_info ~build_outputs ~should_cancel
    (cfg : Pipeline.config) ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  if cfg.compute_proof_diagnostics then
    match run ~build_ast_with_info ~build_outputs cfg with
    | Error _ as e -> e
    | Ok (out : Pipeline.outputs) ->
        on_outputs_ready { out with goals = [] };
        let goal_names = List.map (fun (g, _, _, _, _, _) -> g) out.goals in
        let vc_ids = List.init (List.length out.goals) (fun i -> i + 1) in
        on_goals_ready (goal_names, vc_ids);
        List.iteri
          (fun i (goal, status, time_s, dump_path, source, vcid) ->
            on_goal_done i goal status time_s dump_path source vcid)
          out.goals;
        if should_cancel () then Error (Pipeline.Stage_error "Request cancelled") else Ok out
  else
    match build_ast_with_info ~input_file:cfg.input_file () with
    | Error _ as e -> e
    | Ok (asts, infos) ->
        let pending_cfg = { cfg with prove = false; compute_proof_diagnostics = false } in
        (match build_outputs ~cfg:pending_cfg ~asts ~infos with
        | Error _ as e -> e
        | Ok (pending_out : Pipeline.outputs) ->
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
              if should_cancel () then Error (Pipeline.Stage_error "Request cancelled")
              else
                let goal_results =
                  List.sort
                    (fun (a, _, _, _, _, _, _) (b, _, _, _, _, _, _) -> compare a b)
                    !finished
                in
                Ok
                  (Proof_diagnostics.apply_goal_results_to_outputs ~out:pending_out
                     ~goal_results))
