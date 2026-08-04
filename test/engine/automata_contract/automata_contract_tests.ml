module Automata_exchange = Kr_engine.Kr_engine_automata_contract

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "failed: %s" label
let require_ok label = function Ok value -> value | Error message -> fail "%s: %s" label message

let test_request_round_trip () =
  let formula = Automata_exchange.Always (Implies (Atom "ready", Next (Atom "accepted"))) in
  let request = Automata_exchange.make_request ~atoms:[ "ready"; "accepted" ] formula in
  let json = Automata_exchange.request_to_yojson request in
  let decoded =
    Automata_exchange.request_of_yojson json |> require_ok "automata request JSON round-trip"
  in
  check "request round-trip" (decoded = request);
  require_ok "valid request" (Automata_exchange.validate_request decoded)

let test_response_round_trip_and_validation () =
  let guard = Automata_exchange.Guard_atom "ready" in
  let monitor : Automata_exchange.partial_monitor =
    { initial_state = 0; state_count = 1; transitions = [ { source = 0; guard; target = 0 } ] }
  in
  let response = Automata_exchange.make_response ~atoms:[ "ready" ] monitor in
  require_ok "valid response" (Automata_exchange.validate_response response);
  let decoded =
    Automata_exchange.response_to_yojson response
    |> Automata_exchange.response_of_yojson
    |> require_ok "automata response JSON round-trip"
  in
  check "response round-trip" (decoded = response);
  let invalid_edge =
    {
      response with
      monitor = { response.monitor with transitions = [ { source = 0; guard; target = 2 } ] };
    }
  in
  check "out-of-range edge rejected"
    (Result.is_error (Automata_exchange.validate_response invalid_edge));
  let undeclared_atom =
    {
      response with
      monitor =
        {
          response.monitor with
          transitions = [ { source = 0; guard = Guard_atom "undeclared"; target = 0 } ];
        };
    }
  in
  check "undeclared response atom rejected"
    (Result.is_error (Automata_exchange.validate_response undeclared_atom))

let test_version_rejection () =
  let request = Automata_exchange.make_request ~atoms:[] Automata_exchange.True in
  check "unsupported version rejected"
    (Result.is_error (Automata_exchange.validate_request { request with protocol_version = 0 }))

let () =
  test_request_round_trip ();
  test_response_round_trip_and_validation ();
  test_version_rejection ();
  print_endline "automata_contract_tests: ok"
