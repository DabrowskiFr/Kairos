module Contract = Kairos_proof_contract.Proof_backend_contract

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
  print_endline "why3_adapter_tests: ok"
