module Proof_backend_contract =
  Kairos_proof_contract.Proof_backend_contract

let fail fmt = Printf.ksprintf failwith fmt

let check label condition =
  if not condition then fail "failed: %s" label

let require_ok label = function
  | Ok value -> value
  | Error message -> fail "%s: %s" label message

let test_proof_backend_request_validation () =
  let request =
    Proof_backend_contract.make_request
      ~whyml_text:"module Contract_test\n  goal g : true\nend"
      ()
  in
  require_ok "valid proof backend request"
    (Proof_backend_contract.validate_request request);
  let invalid = { request with whyml_text = "" } in
  check "empty WhyML payloads are rejected"
    (Result.is_error (Proof_backend_contract.validate_request invalid))

let () =
  test_proof_backend_request_validation ();
  print_endline "tool_contract_tests: ok"
