open Kr_domain_core.Kr_domain_core_syntax_builders
open Kr_domain_core
open Kr_verification
open Kr_verification

module Obligations =
  Kr_verification.Kr_verification_obligations

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "failed: %s" label
let require_some label = function
  | Some value -> value
  | None -> fail "missing: %s" label

let single_step_node ~name ~inputs : Kr_domain_core_model.node_model =
  {
    node_name = name;
    methods = [];
    type_decls = [];
    function_decls = [];
    inputs;
    outputs = [];
    locals = [];
    ghosts = [];
    public_ghosts = [];
    states = [ "S" ];
    init_state = "S";
    steps =
      [
        {
          Kr_domain_core_model.src_state = "S";
          dst_state = "S";
          guard_expr = None;
          body_stmts = [];
          elaboration_checks = [];
        };
      ];
    assumes = [];
    guarantees = [];
    state_invariants = [];
  }

let build_reference_product node ~assume_monitor
    ~guarantee_monitor =
  let proof_cases = Kr_verification_cases.minimal [ node ] in
  let automata =
    [
      ( node.Kr_domain_core_model.node_name,
        {
          Kr_verification_automata_types.assume_monitor;
          guarantee_monitor;
        } );
    ]
  in
  let reference_product =
    match
      Kr_verification_orchestration.build_reference_product
        {
          proof_case_program = proof_cases;
          automata;
          reachability_strategy = Kr_verification_reachability.Trivial;
        }
    with
    | Ok reference_product -> reference_product
    | Error message ->
        fail "reference product failed: %s" message
  in
  (proof_cases, reference_product)

let only_product_node reference_product =
  match reference_product.Kr_verification_orchestration.nodes with
  | [ node ] -> node
  | _ -> fail "expected exactly one product node"

let only_instrumented_node reference_product =
  match Kr_verification_orchestration.build_instrumented_ir reference_product with
  | Ok [ node ] -> node
  | Ok _ -> fail "expected exactly one instrumented node"
  | Error message -> fail "instrumentation failed: %s" message

let historical_formula_key formula =
  formula |> Kr_domain_core_formula_simplifier.simplify
  |> Kr_domain_core_formula_simplifier.key_of_hexpr

let history_free_formula_key formula =
  formula |> Kr_domain_core_syntax.historical_of_history_free
  |> historical_formula_key

let test_total_assumption_blocking_yields_no_obligation () =
  let node : Kr_domain_core_model.node_model =
    {
      node_name = "blocked_assumption";
      methods = [];
      type_decls = [];
      function_decls = [];
      inputs = [];
      outputs = [];
      locals = [];
      ghosts = [];
      public_ghosts = [];
      states = [ "S" ];
      init_state = "S";
      steps =
        [
          {
            Kr_domain_core_model.src_state = "S";
            dst_state = "S";
            guard_expr = None;
            body_stmts = [];
            elaboration_checks = [];
          };
        ];
      assumes = [];
      guarantees = [];
      state_invariants = [];
    }
  in
  let assume_monitor : Kr_verification_automata_types.deterministic_partial_monitor =
    { initial_state = 0; state_count = 1; transitions = [] }
  in
  let guarantee_monitor : Kr_verification_automata_types.deterministic_partial_monitor =
    {
      initial_state = 0;
      state_count = 1;
      transitions = [ (0, mk_hbool true, 0) ];
    }
  in
  let automata =
    [
      ( node.node_name,
        {
          Kr_verification_automata_types.assume_monitor;
          guarantee_monitor;
        } );
    ]
  in
  let proof_cases = Kr_verification_cases.minimal [ node ] in
  let reference_product =
    match
      Kr_verification_orchestration.build_reference_product
        {
          proof_case_program = proof_cases;
          automata;
          reachability_strategy = Kr_verification_reachability.Trivial;
        }
    with
    | Ok reference_product -> reference_product
    | Error message ->
        fail "reference product failed: %s" message
  in
  (match reference_product.nodes with
  | [ product_node ] ->
      check "blocked assumption produces no summary"
        (product_node.ir.summaries = [])
  | _ -> fail "expected exactly one product node");
  let instrumented =
    match
      Kr_verification_orchestration.build_instrumented_ir reference_product
    with
    | Ok [ instrumented ] -> instrumented
    | Ok _ -> fail "expected exactly one instrumented node"
    | Error message ->
        fail "instrumentation failed: %s" message
  in
  let partition =
    Obligations.of_instrumented_product_node instrumented
  in
  match
    Obligations.build_program ~proof_cases
      ~partition_inputs:[ partition ]
  with
  | Ok [ obligations ] ->
      check "empty obligation family is accepted"
        (obligations.steps = [])
  | Ok _ -> fail "expected exactly one obligation family"
  | Error message ->
      fail "obligation construction failed: %s" message

let test_raw_states_and_conditional_guarantee_blocking () =
  let gate = mk_hvar "gate" in
  let mode = mk_hvar "mode" in
  let left_guard = mk_hand gate mode in
  let right_guard = mk_hand gate (mk_hnot mode) in
  let node =
    single_step_node ~name:"raw_states"
      ~inputs:
        [
          { Kr_domain_core_syntax.vname = "gate"; vty = TBool };
          { Kr_domain_core_syntax.vname = "mode"; vty = TBool };
        ]
  in
  let assume_monitor :
      Kr_verification_automata_types.deterministic_partial_monitor =
    {
      initial_state = 1;
      state_count = 2;
      transitions = [ (1, mk_hbool true, 1) ];
    }
  in
  let guarantee_monitor :
      Kr_verification_automata_types.deterministic_partial_monitor =
    {
      initial_state = 2;
      state_count = 5;
      transitions =
        [
          (2, left_guard, 3);
          (2, right_guard, 4);
          (3, mk_hbool true, 3);
          (4, mk_hbool true, 4);
        ];
    }
  in
  let _proof_cases, reference_product =
    build_reference_product node ~assume_monitor
      ~guarantee_monitor
  in
  let product_node = only_product_node reference_product in
  let initial = product_node.analysis.exploration.initial_state in
  check "raw initial assumption state is preserved"
    (initial.assume_state_index = 1);
  check "raw initial guarantee state is preserved"
    (initial.guarantee_state_index = 2);
  let initial_summary =
    product_node.ir.summaries
    |> List.find_opt (fun summary ->
           (Kr_verification_ir.product_source summary).guarantee_state_index = 2)
    |> require_some "raw-state summary"
  in
  let destinations =
    initial_summary.product_cases
    |> List.map (fun case ->
           (Kr_verification_ir.product_destination initial_summary case)
             .guarantee_state_index)
    |> List.sort_uniq Int.compare
  in
  check "raw guarantee destinations are preserved"
    (destinations = [ 3; 4 ]);
  let instrumented =
    only_instrumented_node reference_product
  in
  let initial_summary =
    instrumented.ir.summaries
    |> List.find_opt (fun summary ->
           (Kr_verification_ir.product_source summary).guarantee_state_index = 2)
    |> require_some "instrumented raw-state summary"
  in
  let progress =
    initial_summary.ensures
    |> List.find_opt (fun formula ->
           formula.Kr_verification_ir.meta.family
           = Some "guarantee_progress_ensures")
    |> require_some "guarantee progress condition"
  in
  let expected = mk_hor left_guard right_guard in
  check "conditional blocking is the disjunction of outgoing guards"
    (String.equal (history_free_formula_key progress.logic)
       (historical_formula_key expected))

let test_total_guarantee_blocking_is_false_progress () =
  let node =
    single_step_node ~name:"blocked_guarantee" ~inputs:[]
  in
  let assume_monitor :
      Kr_verification_automata_types.deterministic_partial_monitor =
    {
      initial_state = 0;
      state_count = 1;
      transitions = [ (0, mk_hbool true, 0) ];
    }
  in
  let guarantee_monitor :
      Kr_verification_automata_types.deterministic_partial_monitor =
    { initial_state = 0; state_count = 1; transitions = [] }
  in
  let _proof_cases, reference_product =
    build_reference_product node ~assume_monitor
      ~guarantee_monitor
  in
  let product_node = only_product_node reference_product in
  (match product_node.ir.summaries with
  | [ summary ] ->
      check "blocked guarantee has no product case"
        (summary.product_cases = [])
  | _ -> fail "expected one blocked-guarantee summary");
  let instrumented =
    only_instrumented_node reference_product
  in
  let progress =
    match instrumented.ir.summaries with
    | [ summary ] ->
        summary.ensures
        |> List.find_opt (fun formula ->
               formula.Kr_verification_ir.meta.family
               = Some "guarantee_progress_ensures")
        |> require_some "blocking progress condition"
    | _ -> fail "expected one instrumented blocked summary"
  in
  check "absence of guarantee edge yields false progress"
    (match
       (progress.logic
       |> Kr_domain_core_syntax.historical_of_history_free
       |> Kr_domain_core_formula_simplifier.simplify)
         .hexpr
     with
    | Kr_domain_core_syntax.HLitBool false -> true
    | _ -> false)

let () =
  test_total_assumption_blocking_yields_no_obligation ();
  test_raw_states_and_conditional_guarantee_blocking ();
  test_total_guarantee_blocking_is_false_progress ()
