(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

let fail fmt = Printf.ksprintf (fun msg -> prerr_endline msg; exit 1) fmt

let check name condition = if not condition then fail "failed: %s" name

let hvar = Core_syntax_builders.mk_hvar
let hpre = Core_syntax_builders.mk_hpre_k
let hint = Core_syntax_builders.mk_hint
let hcmp op a b = Core_syntax_builders.mk_hexpr (HCmp (op, a, b))
let hand a b = Core_syntax_builders.mk_hand a b
let hor a b = Core_syntax_builders.mk_hor a b
let htrue = Core_syntax_builders.mk_hbool true
let var name vty : Core_syntax.vdecl = { vname = name; vty }
let evar name = Core_syntax_builders.mk_var name

let formula logic = Ir_formula.make logic
let formula_key f = Pretty.string_of_fo (Core_fo_simplifier.simplify f)

let check_equal_formula name expected actual =
  if expected <> actual then
    fail "failed: %s\nexpected: %s\nactual:   %s" name
      (Pretty.string_of_fo expected)
      (Pretty.string_of_fo actual)

let check_equal_string_list name expected actual =
  let normalize = List.sort String.compare in
  let expected = normalize expected in
  let actual = normalize actual in
  if expected <> actual then
    fail "failed: %s\nexpected:\n%s\nactual:\n%s" name
      (String.concat "\n" expected)
      (String.concat "\n" actual)

let string_contains_substring haystack needle =
  let haystack_len = String.length haystack in
  let needle_len = String.length needle in
  if needle_len = 0 then true
  else if needle_len > haystack_len then false
  else
    let rec loop idx =
      if idx + needle_len > haystack_len then false
      else if String.sub haystack idx needle_len = needle then true
      else loop (idx + 1)
    in
    loop 0

let check_raises name expected_substring thunk =
  try
    thunk ();
    fail "failed: %s did not raise" name
  with
  | Failure msg ->
      check name (string_contains_substring msg expected_substring)
  | exn -> fail "failed: %s raised unexpected %s" name (Printexc.to_string exn)

let product_state prog_state guarantee_state_index : Ir.product_state =
  { prog_state; assume_state_index = 0; guarantee_state_index }

let sample_node () : Core_syntax.historical Ir.node_ir =
  let src = product_state "S" 0 in
  let safe_dst = product_state "T" 1 in
  let unsafe_dst_a = product_state "BadA" 2 in
  let unsafe_dst_b = product_state "BadB" 3 in
  let program_step =
    {
      Ir.src_state = "S";
      dst_state = "T";
      guard_expr = None;
      body_stmts = [];
    }
  in
  let summary : Core_syntax.historical Ir.product_step_summary =
    {
      trace = { step_uid = 0 };
      identity = { program_step; product_src = src; assume_guard = htrue };
      propagation_requires = [];
      requires = [];
      ensures = [];
      elaboration_checks = [];
      safe_cases =
        [ { product_dst = safe_dst; admissible_guard = formula (hvar "safe") } ];
      unsafe_cases =
        [
          {
            product_dst = unsafe_dst_a;
            excluded_guard = formula (hor (hvar "bad_a") (hvar "bad_b"));
          };
          { product_dst = unsafe_dst_b; excluded_guard = formula (hvar "bad_c") };
        ];
    }
  in
  {
    semantics =
      {
        sem_nname = "N";
        sem_type_decls = [];
        sem_function_decls = [];
        sem_inputs = [];
        sem_outputs = [];
        sem_locals = [];
        sem_states = [ "S"; "T"; "BadA"; "BadB" ];
        sem_init_state = "S";
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout = [];
    summaries = [ summary ];
    init_invariant_goals = [];
  }

let input_history_node () : Core_syntax.historical Ir.node_ir =
  let src = product_state "S" 0 in
  let dst = product_state "T" 1 in
  let program_step =
    {
      Ir.src_state = "S";
      dst_state = "T";
      guard_expr = Some (evar "i");
      body_stmts = [];
    }
  in
  let summary : Core_syntax.historical Ir.product_step_summary =
    {
      trace = { step_uid = 0 };
      identity =
        { program_step; product_src = src; assume_guard = hvar "assume_i" };
      propagation_requires = [];
      requires = [];
      ensures = [];
      elaboration_checks = [];
      safe_cases = [ { product_dst = dst; admissible_guard = formula (hvar "i") } ];
      unsafe_cases = [];
    }
  in
  let unsafe_summary : Core_syntax.historical Ir.product_step_summary =
    {
      trace = { step_uid = 1 };
      identity =
        {
          program_step =
            {
              Ir.src_state = "T";
              dst_state = "T";
              guard_expr = None;
              body_stmts = [];
            };
          product_src = dst;
          assume_guard = htrue;
        };
      propagation_requires = [];
      requires = [];
      ensures = [];
      elaboration_checks = [];
      safe_cases = [];
      unsafe_cases =
        [
          {
            product_dst = product_state "T" 2;
            excluded_guard = formula (hvar "bad");
          };
        ];
    }
  in
  {
    semantics =
      {
        sem_nname = "InputHistory";
        sem_type_decls = [];
        sem_function_decls = [];
        sem_inputs = [ var "i" TBool; var "assume_i" TBool ];
        sem_outputs = [ var "o" TBool ];
        sem_locals = [];
        sem_states = [ "S"; "T" ];
        sem_init_state = "S";
      };
    source_info =
      {
        assumes = [];
        guarantees = [];
        state_invariants = [ { state = "S"; formula = hvar "o" } ];
      };
    temporal_layout = [];
    summaries = [ summary; unsafe_summary ];
    init_invariant_goals = [];
  }

let parity_transition : Verification_model.program_step =
  {
    src_state = "S";
    dst_state = "T";
    guard_expr = None;
    body_stmts = [];
    elaboration_checks = [];
  }

let parity_model_node () : Verification_model.node_model =
  {
    node_name = "Parity";
    type_decls = [];
    function_decls = [];
    inputs = [];
    outputs = [];
    locals = [];
    ghosts = [];
    public_ghosts = [];
    states = [ "S"; "T" ];
    init_state = "S";
    steps = [ parity_transition ];
    assumes = [];
    guarantees = [];
    state_invariants = [];
  }

let parity_automata () : Automaton_types.automata_spec =
  {
    assume_automaton =
      { states = [ LTrue ]; transitions = [ (0, htrue, 0) ] };
    guarantee_automaton =
      {
        states = [ LTrue; LFalse ];
        transitions = [ (0, hvar "ok", 0); (0, hvar "bad", 1); (1, htrue, 1) ];
      };
  }

let bad_source_model_node () : Verification_model.node_model =
  let loop =
    {
      Verification_model.src_state = "S";
      dst_state = "S";
      guard_expr = None;
      body_stmts = [];
      elaboration_checks = [];
    }
  in
  {
    node_name = "BadSources";
    type_decls = [];
    function_decls = [];
    inputs = [];
    outputs = [];
    locals = [];
    ghosts = [];
    public_ghosts = [];
    states = [ "S" ];
    init_state = "S";
    steps = [ loop ];
    assumes = [];
    guarantees = [];
    state_invariants = [];
  }

let bad_source_automata () : Automaton_types.automata_spec =
  {
    assume_automaton =
      {
        states = [ LTrue; LFalse ];
        transitions =
          [
            (0, hvar "assume_ok", 0);
            (0, hvar "assume_bad", 1);
            (1, htrue, 1);
          ];
      };
    guarantee_automaton =
      {
        states = [ LTrue; LFalse ];
        transitions =
          [
            (0, hvar "guarantee_ok", 0);
            (0, hvar "guarantee_bad", 1);
            (1, htrue, 1);
          ];
      };
  }

let pt_state_key (st : Product_types.product_state) =
  Printf.sprintf "%s/%d/%d" st.prog_state st.assume_state st.guarantee_state

let ir_state_key (st : Ir.product_state) =
  Printf.sprintf "%s/%d/%d" st.prog_state st.assume_state_index st.guarantee_state_index

let program_step_uid (steps : Verification_model.program_step list)
    (step : Verification_model.program_step) =
  let rec loop idx = function
    | [] -> fail "failed: missing program step while computing parity keys"
    | hd :: tl -> if hd = step then idx else loop (idx + 1) tl
  in
  loop 0 steps

let expected_product_case_keys
    ~(analysis : Temporal_automata.node_data)
    ~(program_steps : Verification_model.program_step list) =
  analysis.exploration.steps
  |> List.filter_map (fun (step : Product_types.product_step) ->
         let src_live =
           step.src.assume_state <> analysis.assume_bad_idx
           && step.src.guarantee_state <> analysis.guarantee_bad_idx
         in
         let dst_not_bad_assumption =
           analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx
         in
         if not (src_live && dst_not_bad_assumption) then None
         else
           let case_kind =
             match step.step_class with
             | Safe -> Some "safe"
             | Bad_guarantee -> Some "bad-guarantee"
             | Bad_assumption -> None
           in
           Option.map
             (fun kind ->
               Printf.sprintf "%s|%d|%s|%s|%s|%s" kind
                 (program_step_uid program_steps step.prog_transition)
                 (pt_state_key step.src)
                 (formula_key step.assume_guard)
                 (pt_state_key step.dst)
                 (formula_key step.guarantee_guard))
             case_kind)

let actual_summary_case_keys (node : Core_syntax.historical Ir.node_ir) =
  node.summaries
  |> List.concat_map (fun (summary : Core_syntax.historical Ir.product_step_summary) ->
         let step_uid = summary.trace.step_uid in
         let src = ir_state_key summary.identity.product_src in
         let assume_guard = formula_key summary.identity.assume_guard in
         let safe =
           summary.safe_cases
           |> List.map (fun (case : Core_syntax.historical Ir.safe_product_case) ->
                  Printf.sprintf "safe|%d|%s|%s|%s|%s" step_uid src assume_guard
                    (ir_state_key case.product_dst)
                    (formula_key case.admissible_guard.logic))
         in
         let unsafe =
           summary.unsafe_cases
           |> List.map (fun (case : Core_syntax.historical Ir.unsafe_product_case) ->
                  Printf.sprintf "bad-guarantee|%d|%s|%s|%s|%s" step_uid src
                    assume_guard
                    (ir_state_key case.product_dst)
                    (formula_key case.excluded_guard.logic))
         in
         safe @ unsafe)

let count_bad_contracts : type phase.
    phase Canonical_obligations.step_contract list -> int =
 fun contracts ->
  contracts
  |> List.filter (fun c ->
         c.Canonical_obligations.step_class
         = Canonical_obligations.StepBadGuarantee)
  |> List.length

let find_grouped_bad_contract
    (contracts : Step_contract_projection.step_contract list) =
  List.find_opt
    (fun c ->
      c.Step_contract_projection.step_class
      = Step_contract_projection.StepBadGuarantee)
    contracts

let test_stage2_keeps_unsafe_cases_canonical () =
  let product_summaries =
    sample_node () |> Product_summary_projection.of_ir_node
  in
  let canonical = Canonical_obligations.build_stage2 product_summaries in
  check "canonical safe + two unsafe contracts"
    (List.length canonical.step_contracts = 3);
  check "canonical has one bad-guarantee contract per unsafe case"
    (count_bad_contracts canonical.step_contracts = 2);
  check "canonical unsafe contracts are not split"
    (canonical.step_contracts
    |> List.filter (fun c ->
           c.Canonical_obligations.step_class
           = Canonical_obligations.StepBadGuarantee)
    |> List.for_all
         (fun
           (c :
             Core_syntax.historical Canonical_obligations.step_contract)
         ->
           List.length c.forbidden = 1));
  let grouped =
    sample_node () |> fun node -> Temporal_lower.run_program [ node ]
    |> List.hd |> Step_contract_projection.of_ir_node
  in
  check "grouped view keeps canonical family"
    (count_bad_contracts grouped.canonical.step_contracts = 2);
  check "grouped view has safe + grouped unsafe"
    (List.length grouped.step_contracts = 2);
  match find_grouped_bad_contract grouped.step_contracts with
  | None -> fail "failed: missing grouped bad-guarantee contract"
  | Some bad ->
      check "grouped unsafe covers both canonical unsafe cases"
        (List.length bad.covered_cases = 2);
      check "grouped unsafe may split top-level disjunctions for the backend"
        (List.length bad.forbidden = 3)

let test_temporal_endpoint_shifts () =
  let is_input name = String.equal name "i" in
  let source_formula =
    hand
      (hcmp REq (hvar "i") (hpre "i" 1))
      (hcmp REq (hvar "x") (hpre "x" 2))
  in
  let expected_forward_inputs =
    hand
      (hcmp REq (hpre "i" 1) (hpre "i" 2))
      (hcmp REq (hvar "x") (hpre "x" 3))
  in
  let shifted_forward =
    Fo_time.shift_formula_forward_inputs ~is_input source_formula
  in
  let expected_entry_to_post =
    hand
      (hcmp REq (hvar "i") (hpre "i" 1))
      (hcmp REq (hpre "x" 1) (hpre "x" 2))
  in
  check_equal_formula
    "entry-to-post shift preserves inputs and histories non-inputs"
    expected_entry_to_post
    (Fo_time.shift_formula_entry_to_post ~is_input source_formula);
  check_equal_formula "forward shift moves current inputs into history"
    expected_forward_inputs shifted_forward;
  check_equal_formula "backward shift inverts the forward input shift"
    source_formula
    (Fo_time.shift_formula_backward_inputs ~is_input shifted_forward);
  check_raises "backward shift rejects current input" "current input" (fun () ->
      ignore (Fo_time.shift_formula_backward_inputs ~is_input (hvar "i")))

let test_temporal_endpoint_shift_semantics () =
  let is_input name = String.equal name "i" in
  let eval_read frame (read : Core_syntax.historical Core_syntax.hexpr) =
    match read.hexpr with
    | HVar name -> frame name 0
    | HPreK (name, depth) -> frame name depth
    | _ -> fail "failed: expected a temporal read"
  in
  let source name depth =
    match (name, depth) with
    | "i", 0 -> 3
    | "i", 1 -> 3
    | "i", 2 -> 2
    | "i", _ -> 1
    | "x", 0 -> 10
    | "x", 1 -> 10
    | "x", 2 -> 8
    | "x", _ -> 6
    | _ -> fail "failed: unknown temporal read %s@%d" name depth
  in
  let entry name depth =
    if depth = 0 && String.equal name "i" then 7 else source name depth
  in
  let post name depth =
    if depth = 0 then if String.equal name "i" then 7 else 20
    else source name depth
  in
  let destination name depth =
    if depth <= 1 then post name 0 else source name (depth - 1)
  in
  let reads = [ hvar "i"; hvar "x"; hpre "i" 1; hpre "x" 1; hpre "x" 2 ] in
  List.iter
    (fun read ->
      check "entry-to-post shift preserves read denotation"
        (eval_read post (Fo_time.shift_formula_entry_to_post ~is_input read)
        = eval_read entry read);
      check "forward shift preserves read denotation"
        (eval_read destination (Fo_time.shift_formula_forward_inputs ~is_input read)
        = eval_read post read))
    reads;
  let backward_reads = [ hvar "x"; hpre "i" 1; hpre "x" 1; hpre "x" 2 ] in
  List.iter
    (fun read ->
      check "backward shift preserves read denotation"
        (eval_read post (Fo_time.shift_formula_backward_inputs ~is_input read)
        = eval_read destination read))
    backward_reads

let test_initial_state_requires_history_stability () =
  let node = input_history_node () in
  let enriched =
    match Pre.run_program [ node ] with
    | [ enriched ] -> enriched
    | nodes -> fail "failed: expected one enriched node, got %d" (List.length nodes)
  in
  let initial_summary =
    match
      List.find_opt
        (fun (summary : Core_syntax.historical Ir.product_step_summary) ->
          String.equal summary.identity.product_src.prog_state
            enriched.semantics.sem_init_state)
        enriched.summaries
    with
    | Some summary -> summary
    | None -> fail "failed: missing initial product summary"
  in
  let expected = hcmp REq (hvar "o") (hpre "o" 1) in
  check "initial state requires output/history coherence"
    (List.exists
       (fun (requirement : Core_syntax.historical Ir.summary_formula) ->
         requirement.meta.family = Some "stability_requires"
         && requirement.logic = expected)
       initial_summary.requires)

let test_current_input_frontier () =
  let input_names = [ "i"; "j" ] in
  check "current-input detector ignores historical input"
    (Fo_current_input.no_current_input ~input_names
       (hcmp REq (hpre "i" 1) (hint 0)));
  check "current-input detector rejects current input"
    (not
       (Fo_current_input.no_current_input ~input_names
          (hcmp REq (hvar "i") (hint 0))));
  check_raises "state assertion with current input is rejected" "current inputs"
    (fun () ->
      ignore
        (Fo_current_input.require_no_current_input
           ~context:"test invariant" ~input_names
           (hcmp REq (hvar "j") (hint 0))))

let test_pre_k_layout_and_lowering () =
  let formula =
    hcmp REq
      (hand (hpre "x" 2) (hpre "i" 1))
      (hand (hvar "x") (hpre "flag" 3))
  in
  let temporal_layout =
    Pre_k_layout.build_pre_k_infos_from_parts
      ~inputs:[ var "i" TInt ]
      ~locals:[ var "x" TInt; var "flag" TBool ]
      ~outputs:[] ~fo_formulas:[ formula ] ~ltl:[]
  in
  let slots_for var_name =
    match
      List.find_opt
        (fun (info : Pre_k_layout.pre_k_info) ->
          String.equal info.Pre_k_layout.var_name var_name)
        temporal_layout
    with
    | None -> []
    | Some info -> info.Pre_k_layout.names
  in
  let bindings = Pre_k_lowering.temporal_bindings_of_layout ~temporal_layout in
  check "pre_k layout allocates the maximum depth for x"
    (slots_for "x" = [ "__pre_k1_x"; "__pre_k2_x" ]);
  check "pre_k layout allocates the maximum depth for flag"
    (slots_for "flag"
    = [ "__pre_k1_flag"; "__pre_k2_flag"; "__pre_k3_flag" ]);
  let expected =
    hcmp REq
      (hand (hvar "__pre_k2_x") (hvar "__pre_k1_i"))
      (hand (hvar "x") (hvar "__pre_k3_flag"))
  in
  match Pre_k_lowering.lower_fo_formula_temporal_bindings ~temporal_bindings:bindings formula with
  | None -> fail "failed: pre_k lowering unexpectedly failed"
  | Some lowered ->
      check_equal_formula "pre_k lowering rewrites historical references to slots"
        expected lowered

let test_product_characteristics_entry_facts_shift_current_inputs () =
  let node = input_history_node () in
  let table = Product_characteristics.build ~node in
  let dst = product_state "T" 1 in
  match Product_characteristics.entry_facts_of_product_state table dst with
  | [ fact ] ->
      check "entry fact generated from current input is a historical fact"
        (Fo_current_input.no_current_input
           ~input_names:[ "i"; "assume_i" ] fact);
      check_equal_formula
        "entry fact retains the source annotation, assumption guard, and body effect"
        (hand
           (hand
              (hand (hpre "assume_i" 1) (hpre "i" 1))
              (hpre "o" 2))
           (hcmp REq (hvar "o") (hpre "o" 2)))
        fact
  | facts ->
      fail "failed: expected one entry fact, got %d" (List.length facts)

let test_product_exploration_and_summary_parity () =
  let node = parity_model_node () in
  let automata = parity_automata () in
  let analysis =
    Product_build.analyze_node ~build:automata ~node ~program_transitions:node.steps
  in
  let expected = expected_product_case_keys ~analysis ~program_steps:node.steps in
  let node_ir =
    match From_model.of_model_program ~automata:[ (node.node_name, automata) ] [ node ] with
    | Ok [ node_ir ] -> node_ir
    | Ok nodes -> fail "failed: expected one IR node, got %d" (List.length nodes)
    | Error msg -> fail "failed: From_model rejected parity node: %s" msg
  in
  check_equal_string_list "product exploration and summaries expose the same cases"
    expected (actual_summary_case_keys node_ir)

let test_bad_product_sources_do_not_generate_summaries () =
  let node = bad_source_model_node () in
  let automata = bad_source_automata () in
  let analysis =
    Product_build.analyze_node ~build:automata ~node
      ~program_transitions:node.steps
  in
  check "product exploration retains edges from bad sources"
    (List.exists
       (fun (step : Product_types.product_step) ->
         step.src.assume_state = analysis.assume_bad_idx
         || step.src.guarantee_state = analysis.guarantee_bad_idx)
       analysis.exploration.steps);
  let node_ir =
    match
      From_model.of_model_program
        ~automata:[ (node.node_name, automata) ] [ node ]
    with
    | Ok [ node_ir ] -> node_ir
    | Ok nodes -> fail "failed: expected one IR node, got %d" (List.length nodes)
    | Error msg -> fail "failed: From_model rejected bad-source node: %s" msg
  in
  check "active source still generates summaries" (node_ir.summaries <> []);
  check "summary sources are active"
    (List.for_all
       (fun (summary : Core_syntax.historical Ir.product_step_summary) ->
         summary.identity.product_src.assume_state_index
           <> analysis.assume_bad_idx
         && summary.identity.product_src.guarantee_state_index
              <> analysis.guarantee_bad_idx)
       node_ir.summaries);
  check "assumption-bad destinations generate no cases"
    (List.for_all
       (fun (summary : Core_syntax.historical Ir.product_step_summary) ->
         List.for_all
           (fun (case : Core_syntax.historical Ir.safe_product_case) ->
             case.product_dst.assume_state_index <> analysis.assume_bad_idx)
           summary.safe_cases
         && List.for_all
              (fun (case : Core_syntax.historical Ir.unsafe_product_case) ->
                case.product_dst.assume_state_index
                  <> analysis.assume_bad_idx)
              summary.unsafe_cases)
       node_ir.summaries);
  check "active-to-safe cases remain"
    (List.exists
       (fun (summary : Core_syntax.historical Ir.product_step_summary) ->
         summary.safe_cases <> [])
       node_ir.summaries);
  check "active-to-bad-guarantee cases remain as exclusions"
    (List.exists
       (fun (summary : Core_syntax.historical Ir.product_step_summary) ->
         summary.unsafe_cases <> [])
       node_ir.summaries)

let test_product_automata_normal_form_validation () =
  let node = parity_model_node () in
  let valid = parity_automata () in
  let analyze build =
    ignore (Product_build.analyze_node ~build ~node ~program_transitions:node.steps)
  in
  let duplicate_assumption_targets =
    {
      valid with
      assume_automaton =
        {
          states = [ LTrue; LTrue ];
          transitions = [ (0, htrue, 0); (0, htrue, 1) ];
        };
    }
  in
  check_raises "same-guard assumption targets are rejected" "same-guard"
    (fun () -> analyze duplicate_assumption_targets);
  let empty_assumption =
    {
      valid with
      assume_automaton = { states = []; transitions = [] };
    }
  in
  check_raises "empty automata are rejected" "has no states" (fun () ->
      analyze empty_assumption);
  let bad_initial_assumption =
    {
      valid with
      assume_automaton =
        { states = [ LFalse ]; transitions = [ (0, htrue, 0) ] };
    }
  in
  check_raises "bad initial assumption state is rejected" "bad initial state"
    (fun () -> analyze bad_initial_assumption);
  let bad_initial_guarantee =
    {
      valid with
      guarantee_automaton =
        { states = [ LFalse ]; transitions = [ (0, htrue, 0) ] };
    }
  in
  check_raises "bad initial guarantee state is rejected" "bad initial state"
    (fun () -> analyze bad_initial_guarantee);
  let non_absorbing_bad_guarantee =
    {
      valid with
      guarantee_automaton =
        {
          states = [ LTrue; LFalse ];
          transitions = [ (0, htrue, 1); (1, htrue, 0) ];
        };
    }
  in
  analyze non_absorbing_bad_guarantee;
  let non_absorbing_bad_assumption =
    {
      valid with
      assume_automaton =
        {
          states = [ LTrue; LFalse ];
          transitions = [ (0, htrue, 1); (1, htrue, 0) ];
        };
    }
  in
  check_raises "assumption bad state must be absorbing" "must be absorbing"
    (fun () -> analyze non_absorbing_bad_assumption);
  let multiple_bad_guarantee =
    {
      valid with
      guarantee_automaton =
        {
          states = [ LTrue; LFalse; LFalse ];
          transitions = [ (0, htrue, 1); (1, htrue, 1); (2, htrue, 2) ];
        };
    }
  in
  check_raises "multiple bad states are rejected" "multiple bad states" (fun () ->
      analyze multiple_bad_guarantee)

let () =
  test_stage2_keeps_unsafe_cases_canonical ();
  test_temporal_endpoint_shifts ();
  test_temporal_endpoint_shift_semantics ();
  test_initial_state_requires_history_stability ();
  test_current_input_frontier ();
  test_pre_k_layout_and_lowering ();
  test_product_characteristics_entry_facts_shift_current_inputs ();
  test_product_exploration_and_summary_parity ();
  test_bad_product_sources_do_not_generate_summaries ();
  test_product_automata_normal_form_validation ();
  print_endline "canonical_obligations_tests: ok"
