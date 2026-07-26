module Contract = Kairos_proof_contract.Proof_backend_contract

let check label condition = if not condition then failwith ("failed: " ^ label)

let () =
  let request =
    Contract.make_request ~whyml_text:"module Contract_smoke\n  goal emitted : false\nend" ()
  in
  let response = Why_obligations.run request in
  check "response version" (Result.is_ok (Contract.validate_response response));
  check "Why3 obligation produced" (String.trim response.vc_text <> "");
  check "SMT obligation produced" (String.trim response.smt_text <> "");
  print_endline "why3_adapter_tests: ok"
