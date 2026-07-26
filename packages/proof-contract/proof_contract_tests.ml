module Contract = Kairos_proof_contract.Proof_backend_contract

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "failed: %s" label
let require_ok label = function Ok value -> value | Error message -> fail "%s: %s" label message

let () =
  let request =
    Contract.make_request ~filename:"input.mlw" ~whyml_text:"module M\n  goal g : true\nend" ()
  in
  require_ok "valid request" (Contract.validate_request request);
  check "empty WhyML rejected"
    (Result.is_error (Contract.validate_request { request with whyml_text = " " }));
  let encoded = Contract.request_to_yojson request in
  let decoded = require_ok "request JSON" (Contract.request_of_yojson encoded) in
  check "request JSON round trip" (decoded = request);
  let response = Contract.make_response ~vc_text:"goal" ~smt_text:"(check-sat)" in
  require_ok "valid response" (Contract.validate_response response);
  print_endline "proof_contract_tests: ok"
