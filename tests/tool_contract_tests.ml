module Why3_contract = Kairos_why3_contract.Why3_contract

let fail fmt = Printf.ksprintf failwith fmt

let check label condition =
  if not condition then fail "failed: %s" label

let require_ok label = function
  | Ok value -> value
  | Error message -> fail "%s: %s" label message

let test_proof_backend_request_validation () =
  let options : Why3_contract.execution_options =
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
  let request =
    Why3_contract.make_execution_request
      ~whyml_text:"module Contract_test\n  goal g : true\nend"
      ~options ()
  in
  require_ok "valid proof backend request"
    (Why3_contract.validate_execution_request request);
  let invalid = { request with whyml_text = "" } in
  check "empty WhyML payloads are rejected"
    (Result.is_error
       (Why3_contract.validate_execution_request invalid))

let () =
  test_proof_backend_request_validation ();
  print_endline "tool_contract_tests: ok"
