module Automata_exchange = Kairos_tool_contracts.Automata_exchange
module Proof_backend_contract =
  Kairos_tool_contracts.Proof_backend_contract

let fail fmt = Printf.ksprintf failwith fmt

let check label condition =
  if not condition then fail "failed: %s" label

let require_ok label = function
  | Ok value -> value
  | Error message -> fail "%s: %s" label message

let test_automata_request_round_trip () =
  let request =
    Automata_exchange.make_request ~atom_map:[] Core_syntax.LTrue
  in
  let json = Automata_exchange.request_to_yojson request in
  let decoded =
    Automata_exchange.request_of_yojson json
    |> require_ok "automata request JSON round-trip"
  in
  check "automata request JSON round-trip preserves the request"
    (decoded = request);
  require_ok "valid automata request"
    (Automata_exchange.validate_request decoded)

let test_automata_response_validation () =
  let guard : Core_syntax.hexpr =
    { hexpr = Core_syntax.HLitBool true; loc = None }
  in
  let automaton : Automata_exchange.automaton =
    {
      initial_state = 0;
      states = [ Accepting; Rejecting ];
      transitions =
        [
          { source = 0; guard; target = 1 };
          { source = 1; guard; target = 1 };
        ];
    }
  in
  let response = Automata_exchange.make_response automaton in
  require_ok "valid automata response"
    (Automata_exchange.validate_response response);
  let json = Automata_exchange.response_to_yojson response in
  let decoded =
    Automata_exchange.response_of_yojson json
    |> require_ok "automata response JSON round-trip"
  in
  check "automata response JSON round-trip preserves the response"
    (decoded = response);
  let invalid =
    {
      response with
      automaton =
        {
          response.automaton with
          transitions = [ { source = 0; guard; target = 2 } ];
        };
    }
  in
  check "out-of-range automata edges are rejected"
    (Result.is_error (Automata_exchange.validate_response invalid))

let test_contract_version_rejection () =
  let request =
    Automata_exchange.make_request ~atom_map:[] Core_syntax.LTrue
  in
  let invalid = { request with protocol_version = 0 } in
  check "unsupported contract versions are rejected"
    (Result.is_error (Automata_exchange.validate_request invalid))

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
  test_automata_request_round_trip ();
  test_automata_response_validation ();
  test_contract_version_rejection ();
  test_proof_backend_request_validation ();
  print_endline "tool_contract_tests: ok"
