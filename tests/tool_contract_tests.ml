module Proof_backend_contract =
  Kairos_tool_contracts.Proof_backend_contract

let fail fmt = Printf.ksprintf failwith fmt

let check label condition =
  if not condition then fail "failed: %s" label

let require_ok label = function
  | Ok value -> value
  | Error message -> fail "%s: %s" label message

let test_proof_backend_request_validation () =
  let optimizations : Proof_backend_contract.optimization_policy =
    {
      share_facts = true;
      simplify_formulas = true;
      slice_transition_bodies = true;
      simplify_runtime_actions = true;
      deduplicate_terms = true;
      group_product_steps = true;
      product_step_group_max_cost = 0;
    }
  in
  let request =
    Proof_backend_contract.make_request ~nodes:[] ~optimizations
  in
  require_ok "valid proof backend request"
    (Proof_backend_contract.validate_request request);
  let invalid =
    {
      request with
      optimizations =
        { optimizations with product_step_group_max_cost = -1 };
    }
  in
  check "negative proof grouping costs are rejected"
    (Result.is_error (Proof_backend_contract.validate_request invalid))

let () =
  test_proof_backend_request_validation ();
  print_endline "tool_contract_tests: ok"
