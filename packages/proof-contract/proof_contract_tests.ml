module Contract = Kairos_proof_contract.Proof_backend_contract

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "failed: %s" label
let require_ok label = function Ok value -> value | Error message -> fail "%s: %s" label message

let () =
  let whyml_text = "module M\n  goal g : true\nend" in
  let options : Contract.execution_options =
    {
      timeout_s = 5;
      jobs = 2;
      split_vc = true;
      dump_failed_smt = false;
      prove = true;
      emit_vc_text = true;
      emit_smt_text = true;
      diagnose_nonvalid = false;
    }
  in
  let execution_request =
    Contract.make_execution_request ~filename:"input.mlw" ~whyml_text ~options ()
  in
  require_ok "valid execution request" (Contract.validate_execution_request execution_request);
  check "empty WhyML rejected"
    (Result.is_error
       (Contract.validate_execution_request { execution_request with whyml_text = " " }));
  check "non-positive worker count rejected"
    (Result.is_error
       (Contract.validate_execution_request
          { execution_request with options = { options with jobs = 0 } }));
  let execution_json = Contract.execution_request_to_yojson execution_request in
  let decoded_execution =
    require_ok "execution JSON" (Contract.execution_request_of_yojson execution_json)
  in
  check "execution JSON round trip" (decoded_execution = execution_request);
  print_endline "proof_contract_tests: ok"
