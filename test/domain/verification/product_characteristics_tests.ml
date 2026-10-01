open Kr_domain_core.Kr_domain_core_syntax
open Kr_domain_core.Kr_domain_core_syntax_builders
open Kr_verification

let product_state assume_state_index guarantee_state_index : Kr_verification.Kr_verification_ir.product_state =
  {
    prog_state = "S";
    assume_state_index;
    guarantee_state_index;
  }

let summary_formula oid logic : Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.summary_formula =
  {
    logic;
    meta = { oid; loc = None; family = None };
  }

let transition : Kr_verification.Kr_verification_ir.transition =
  {
    src_state = "S";
    dst_state = "S";
    guard_expr = None;
    body_stmts = [];
  }

let summary ~step_uid ~(src : Kr_verification.Kr_verification_ir.product_state)
    ~assume_destination_state_index
    product_cases :
    Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.product_step_summary =
  {
    trace = { step_uid };
    identity =
      {
        program_step = transition;
        monitor_source =
          {
            assume_state_index = src.assume_state_index;
            guarantee_state_index =
              src.guarantee_state_index;
          };
        assume_destination_state_index;
        assume_guard = mk_hbool true;
      };
    propagation_requires = [];
    requires = [];
    ensures = [];
    elaboration_checks = [];
    product_cases;
  }

let test_exact_initial_state_is_not_characterized () =
  let actual_initial = product_state 4 7 in
  let zero_indexed_state = product_state 0 0 in
  let incoming_case : Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.product_case =
    {
      guarantee_destination_state_index =
        actual_initial.guarantee_state_index;
      guarantee_guard = summary_formula 1 (mk_hvar "gate");
    }
  in
  let node : Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.node_ir =
    {
      semantics =
        {
          sem_nname = "nonzero_initial";
          sem_type_decls = [];
          sem_function_decls = [];
          sem_inputs = [ { vname = "gate"; vty = TBool } ];
          sem_outputs = [];
          sem_locals = [];
          sem_states = [ "S" ];
          sem_init_state = "S";
          sem_methods = [];
        };
      source_info =
        { assumes = []; guarantees = []; state_invariants = [] };
      temporal_layout = [];
      summaries =
        [
          summary ~step_uid:0 ~src:zero_indexed_state
            ~assume_destination_state_index:
              actual_initial.assume_state_index
            [ incoming_case ];
          summary ~step_uid:1 ~src:actual_initial
            ~assume_destination_state_index:
              actual_initial.assume_state_index
            [];
        ];
    }
  in
  let table_with_other_initial =
    Kr_verification_characteristics.build ~body_effect_summaries:false
      ~initial_state:zero_indexed_state
      ~node
  in
  assert (
    Kr_verification_characteristics.entry_facts_of_product_state
      table_with_other_initial actual_initial
    <> []);
  let table =
    Kr_verification_characteristics.build ~body_effect_summaries:false
      ~initial_state:actual_initial ~node
  in
  assert (
    Kr_verification_characteristics.entry_facts_of_product_state table
      actual_initial
    = [])

let assert_formulas_equal expected actual =
  (* Simplification preserves meaning, but need not choose one Boolean order. *)
  let rec formula_key formula =
    match formula.hexpr with
    | HBin ((And | Or as operator), _, _) ->
        let rec terms formula =
          match formula.hexpr with
          | HBin (candidate, left, right) when candidate = operator ->
              terms left @ terms right
          | _ -> [ formula_key formula ]
        in
        let name = if operator = And then "and" else "or" in
        Printf.sprintf "%s(%s)" name
          (terms formula |> List.sort_uniq String.compare |> String.concat ",")
    | _ -> Kr_domain_core.Kr_domain_core_formula_simplifier.key_of_hexpr formula
  in
  let keys formulas =
    List.map
      (fun formula ->
        formula
        |> Kr_domain_core.Kr_domain_core_formula_simplifier.simplify
        |> formula_key)
      formulas
  in
  let expected = keys expected in
  let actual = keys actual in
  if expected <> actual then
    failwith
      (Printf.sprintf "expected formulas [%s], got [%s]"
         (String.concat "; " expected) (String.concat "; " actual))

let nonnegative value = mk_hexpr (HCmp (RGe, value, mk_hint 0))

let increment_effect depth =
  mk_hexpr
    (HCmp
       (REq, mk_hvar "x", mk_hexpr (HBin (Add, mk_hpre_k "x" depth, mk_hint 1))))

let increment_node ~guard_expr ~assume_guard ~guarantee_guard =
  let initial_state = product_state 0 0 in
  let destination = product_state 0 1 in
  let incoming_case : historical Kr_verification_ir.product_case =
    {
      guarantee_destination_state_index = 1;
      guarantee_guard = summary_formula 2 guarantee_guard;
    }
  in
  let incoming =
    summary ~step_uid:0 ~src:initial_state
      ~assume_destination_state_index:0 [ incoming_case ]
  in
  let incoming =
    {
      incoming with
      identity =
        {
          incoming.identity with
          program_step =
            {
              transition with
              guard_expr;
              body_stmts =
                [
                  {
                    stmt =
                      SAssign ("x", mk_expr (EBin (Add, mk_var "x", mk_int 1)));
                    loc = None;
                  };
                ];
            };
          assume_guard;
        };
    }
  in
  let node : historical Kr_verification_ir.node_ir =
    {
      semantics =
        {
          sem_nname = "increment";
          sem_type_decls = [];
          sem_function_decls = [];
          sem_inputs =
            [ { vname = "gate"; vty = TBool }; { vname = "sample"; vty = TBool } ];
          sem_outputs = [ { vname = "x"; vty = TInt } ];
          sem_locals = [];
          sem_states = [ "S" ];
          sem_init_state = "S";
          sem_methods = [];
        };
      source_info =
        {
          assumes = [];
          guarantees = [];
          state_invariants = [ { state = "S"; formula = nonnegative (mk_hvar "x") } ];
        };
      temporal_layout = [];
      summaries =
        [
          incoming;
          summary ~step_uid:1 ~src:destination
            ~assume_destination_state_index:0 [];
        ];
    }
  in
  (initial_state, destination, node, incoming)

let test_body_effect_summaries_are_opt_in () =
  let initial_state, destination, node, incoming =
    increment_node ~guard_expr:None ~assume_guard:(mk_hbool true)
      ~guarantee_guard:(mk_hbool true)
  in
  let build body_effect_summaries =
    Kr_verification_characteristics.build ~body_effect_summaries ~initial_state
      ~node
  in
  let without_effects = build false in
  let with_effects = build true in
  let without_effects_again = build false in
  let check table ~entry ~preservation =
    assert_formulas_equal [ entry ]
      (Kr_verification_characteristics.entry_facts_of_product_state table
         destination);
    assert_formulas_equal [ preservation ]
      (Kr_verification_characteristics.preservation_ensures table ~node incoming)
  in
  let entry = nonnegative (mk_hpre_k "x" 2) in
  let preservation = nonnegative (mk_hpre_k "x" 1) in
  check without_effects ~entry ~preservation;
  check with_effects ~entry:(mk_hand entry (increment_effect 2))
    ~preservation:(mk_hand preservation (increment_effect 1));
  check without_effects_again ~entry ~preservation

let test_disabled_effects_retain_annotation_and_guard_facts () =
  let guarantee_guard =
    mk_hexpr (HCmp (RGe, mk_hvar "x", mk_hpre_k "x" 1))
  in
  let initial_state, destination, node, incoming =
    increment_node ~guard_expr:(Some (mk_var "gate"))
      ~assume_guard:(mk_hand (mk_hvar "sample") (mk_hpre_k "sample" 1))
      ~guarantee_guard
  in
  let table =
    Kr_verification_characteristics.build ~body_effect_summaries:false
      ~initial_state ~node
  in
  let contribution =
    mk_hand
      (mk_hand
        (mk_hand (nonnegative (mk_hpre_k "x" 1)) (mk_hvar "gate"))
        (mk_hand (mk_hvar "sample") (mk_hpre_k "sample" 1)))
      guarantee_guard
  in
  let entry =
    mk_hand
      (mk_hand
        (mk_hand (nonnegative (mk_hpre_k "x" 2)) (mk_hpre_k "gate" 1))
        (mk_hand (mk_hpre_k "sample" 1) (mk_hpre_k "sample" 2)))
      (mk_hexpr (HCmp (RGe, mk_hvar "x", mk_hpre_k "x" 2)))
  in
  assert_formulas_equal [ entry ]
    (Kr_verification_characteristics.entry_facts_of_product_state table destination);
  assert_formulas_equal [ mk_himp guarantee_guard contribution ]
    (Kr_verification_characteristics.preservation_ensures table ~node incoming)

let () =
  test_exact_initial_state_is_not_characterized ();
  test_body_effect_summaries_are_opt_in ();
  test_disabled_effects_retain_annotation_and_guard_facts ()
