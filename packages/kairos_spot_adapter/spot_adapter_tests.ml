module Contract = Kairos_automata_contract.Automata_exchange
module Spot = Kairos_spot_adapter.Automaton_spot
module Valuation = Kairos_spot_adapter.Spot_boolean_valuation

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "failed: %s" label

let test_ltl_rendering () =
  let formula = Contract.Always (Implies (Atom "ready", Next (Atom "accepted"))) in
  let rendered = Spot.string_of_spot_ltl ~atom_names:[ "ready"; "accepted" ] formula in
  check "neutral LTL rendering" (String.equal rendered "G(__kairos_ap_0 -> X(__kairos_ap_1))")

let test_hoa_parsing_and_guard_conversion () =
  let hoa =
    Spot.parse_hoa
      "HOA: v1\n\
       Start: 0\n\
       AP: 1 \"__kairos_ap_0\"\n\
       Acceptance: 0 t\n\
       --BODY--\n\
       State: 0\n\
       [0] 0\n\
       --END--\n"
  in
  check "HOA start" (hoa.start = 0);
  check "HOA AP count" (hoa.ap_count = 1);
  let state = List.hd hoa.states in
  let label, target = List.hd state.transitions in
  check "HOA target" (target = 0);
  let raw = Spot.raw_guard_of_label ~atom_names:[ "ready" ] ~hoa_ap_names:hoa.ap_names label in
  check "HOA label uses neutral atom" (Valuation.terms_to_guard raw = Contract.Guard_atom "ready")

let () =
  test_ltl_rendering ();
  test_hoa_parsing_and_guard_conversion ();
  print_endline "spot_adapter_tests: ok"
