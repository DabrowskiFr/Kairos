let fail message =
  prerr_endline ("engine_callback_tests: " ^ message);
  exit 1

let () =
  if Array.length Sys.argv <> 2 then fail "expected one Kairos input path";
  let input_file = Sys.argv.(1) in
  let config =
    Kairos_engine.Api.make_config ~input_file ~wp_only:false
      ~smoke_tests:false ~timeout_s:1 ~compute_proof_diagnostics:false
      ~prove:false ~generate_vc_text:false ~generate_smt_text:false
      ~generate_dot_png:false ()
  in
  let events = ref [] in
  let callback_outputs = ref None in
  let callback_goals = ref None in
  let completed = ref [] in
  let on_outputs_ready outputs =
    events := !events @ [ "outputs" ];
    callback_outputs := Some outputs
  in
  let on_goals_ready goals =
    events := !events @ [ "goals" ];
    callback_goals := Some goals
  in
  let on_goal_done index name status time_s dump_path vc_id =
    events := !events @ [ "goal_done" ];
    completed := !completed @ [ (index, name, status, time_s, dump_path, vc_id) ]
  in
  match
    Kairos_engine.Api.run_with_callbacks ~should_cancel:(fun () -> false)
      config ~on_outputs_ready ~on_goals_ready ~on_goal_done
  with
  | Error error -> fail (Kairos_engine.Api.error_to_string error)
  | Ok outputs ->
      let callback_outputs =
        match !callback_outputs with
        | Some value -> value
        | None -> fail "on_outputs_ready was not called"
      in
      let callback_names, callback_ids =
        match !callback_goals with
        | Some value -> value
        | None -> fail "on_goals_ready was not called"
      in
      if callback_outputs.goals <> [] then
        fail "the early output callback must not duplicate completed goals";
      let expected_names =
        List.map
          (fun (name, _, _, _, _) -> name)
          outputs.Kairos_engine.Api.Contract.goals
      in
      if callback_names <> expected_names then
        fail "goal names differ between callback and final output";
      if callback_ids <> outputs.vc_ids_ordered then
        fail "VC identifiers differ between callback and final output";
      if List.length !completed <> List.length outputs.goals then
        fail "goal completion callback count differs from final output";
      (match !events with
      | "outputs" :: "goals" :: _ -> ()
      | _ -> fail "callbacks were not emitted in outputs/goals order")
