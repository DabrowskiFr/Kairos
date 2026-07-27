module Contract = Kairos_why3_contract.Why3_contract

let check label condition = if not condition then failwith ("failed: " ^ label)

let () =
  let options : Contract.execution_options =
    {
      timeout_s = 5;
      jobs = 1;
      split_vc = true;
      dump_failed_smt = false;
      prove = false;
      emit_vc_text = true;
      emit_smt_text = true;
      diagnose_nonvalid = false;
    }
  in
  let execution_request =
    Contract.make_execution_request
      ~whyml_text:"module Contract_execution\n  goal emitted : false\nend" ~options ()
  in
  let execution = Why_execution.execute execution_request in
  check "execution response version" (Result.is_ok (Contract.validate_execution_response execution));
  check "neutral goal descriptor produced" (List.length execution.goals = 1);
  check "proof disabled means no results" (execution.results = []);
  check "execution VC emitted" (List.length execution.vc_blocks = 1);
  check "execution SMT emitted" (List.length execution.smt_blocks = 1);
  check "task extraction timing returned" (execution.metrics.task_extract_s >= 0.0);
  check "proof-disabled metrics contain no prover call" (execution.metrics.prover_goal_count = 0);
  check "proof-disabled metrics contain no worker" (execution.metrics.workers = []);
  let encoded = Contract.execution_response_to_yojson execution in
  let decoded =
    match Contract.execution_response_of_yojson encoded with
    | Ok response -> response
    | Error message -> failwith message
  in
  check "execution metrics survive protocol serialization" (decoded.metrics = execution.metrics);
  print_endline "why3_adapter_tests: ok"
