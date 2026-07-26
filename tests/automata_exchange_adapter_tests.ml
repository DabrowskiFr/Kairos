module Contract = Kairos_automata_contract.Automata_exchange

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "failed: %s" label

let test_core_contract_round_trip_boundary () =
  let open Core_syntax in
  let open Core_syntax_builders in
  let atom = (mk_hvar "counter", RGt, mk_hint 0) in
  let atom_map = [ (atom, "counter_positive") ] in
  let request = Automata_exchange_adapter.request_of_core ~atom_map (LG (LAtom atom)) in
  check "request atom domain" (request.atoms = [ "counter_positive" ]);
  check "request formula is neutral" (request.formula = Contract.Always (Atom "counter_positive"));
  let response =
    Contract.make_response ~atoms:request.atoms
      {
        initial_state = 0;
        states = [ Accepting ];
        transitions =
          [ { source = 0; guard = Guard_not (Guard_atom "counter_positive"); target = 0 } ];
      }
  in
  let converted = Automata_exchange_adapter.automaton_of_response ~atom_map response in
  let expected_guard =
    let left, relation, right = atom in
    mk_hnot (mk_hexpr (HCmp (relation, left, right)))
  in
  check "response state conversion" (converted.states = [ LTrue ]);
  check "response guard conversion" (converted.transitions = [ (0, expected_guard, 0) ])

let test_response_atom_substitution_is_rejected () =
  let open Core_syntax in
  let open Core_syntax_builders in
  let atom = (mk_hvar "ready", REq, mk_hbool true) in
  let response =
    Contract.make_response ~atoms:[ "other" ]
      {
        initial_state = 0;
        states = [ Accepting ];
        transitions = [ { source = 0; guard = Guard_atom "other"; target = 0 } ];
      }
  in
  check "response atom-domain substitution rejected"
    (try
       ignore
         (Automata_exchange_adapter.automaton_of_response ~atom_map:[ (atom, "ready") ] response);
       false
     with Invalid_argument _ -> true)

let () =
  test_core_contract_round_trip_boundary ();
  test_response_atom_substitution_is_rejected ();
  print_endline "automata_exchange_adapter_tests: ok"
