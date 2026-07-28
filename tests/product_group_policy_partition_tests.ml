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

open Core_syntax

let fail fmt = Printf.ksprintf (fun msg -> prerr_endline msg; exit 1) fmt
let check name condition = if not condition then fail "failed: %s" name

let history_free_true : history_free hexpr =
  { hexpr = HLitBool true; loc = None }

let hvar name : history_free hexpr = { hexpr = HVar name; loc = None }
let formula name = Ir_formula.make (hvar name)
let hnot formula : history_free hexpr =
  { hexpr = HUn (Not, formula); loc = None }

let hor left right : history_free hexpr =
  { hexpr = HBin (Or, left, right); loc = None }

let product_state prog_state : Ir.product_state =
  {
    prog_state;
    assume_state_index = 0;
    guarantee_state_index = 0;
  }

let loop : Ir.transition =
  {
    src_state = "S";
    dst_state = "S";
    guard_expr = None;
    body_stmts = [];
  }

let branch : Ir.transition =
  {
    src_state = "S";
    dst_state = "T";
    guard_expr = None;
    body_stmts = [];
  }

let model_step (transition : Ir.transition) : Verification_model.program_step =
  {
    src_state = transition.src_state;
    dst_state = transition.dst_state;
    guard_expr = transition.guard_expr;
    body_stmts = transition.body_stmts;
    elaboration_checks = [];
  }

let source_node : Verification_model.node_model =
  {
    node_name = "Source";
    type_decls = [];
    function_decls = [];
    inputs = [];
    outputs = [];
    locals = [];
    ghosts = [];
    public_ghosts = [];
    states = [ "S"; "T" ];
    init_state = "S";
    steps = [ model_step loop; model_step branch ];
    assumes = [];
    guarantees = [];
    state_invariants = [];
  }

type outcome =
  | Safe
  | Bad_guarantee

let safe_case destination : history_free Ir.safe_product_case =
  {
    product_dst = product_state destination;
    admissible_guard = Ir_formula.make history_free_true;
  }

let unsafe_case destination guard :
    history_free Ir.unsafe_product_case =
  {
    product_dst = product_state destination;
    excluded_guard = formula guard;
  }

let summary ?(program_step = loop) ?(requires = []) ?(ensures = [])
    ?(outcome = Safe) ~step_uid ~assume_guard () :
    history_free Ir.product_step_summary =
  let safe_cases, unsafe_cases =
    match outcome with
    | Safe -> ([ safe_case program_step.dst_state ], [])
    | Bad_guarantee ->
        ( [],
          [
            unsafe_case program_step.dst_state
              ("excluded_" ^ assume_guard);
          ] )
  in
  {
    trace = { step_uid };
    identity =
      {
        program_step;
        product_src = product_state program_step.src_state;
        assume_guard = hvar assume_guard;
      };
    propagation_requires = [];
    requires = List.map formula requires;
    ensures = List.map formula ensures;
    elaboration_checks = [];
    safe_cases;
    unsafe_cases;
  }

let runtime_node name summaries : history_free Ir.node_ir =
  {
    semantics =
      {
        sem_nname = name;
        sem_type_decls = [];
        sem_function_decls = [];
        sem_inputs = [];
        sem_outputs = [];
        sem_locals = [];
        sem_states = [ "S"; "T" ];
        sem_init_state = "S";
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout = [];
    summaries;
    init_invariant_goals = [];
  }

let partition name summaries : Proof_plan.partition_input =
  {
    source_node_name = source_node.node_name;
    node = runtime_node name summaries;
  }

let only name = function
  | [ value ] -> value
  | values ->
      fail "failed: %s: expected one value, got %d" name
        (List.length values)

let build ?(group = true) partition_inputs =
  Proof_plan.build_program
    ~policy:{ group_safe_step_contracts = group }
    ~source_model:[ source_node ] ~partition_inputs
  |> only "proof plan"

let guard_name (member : Proof_plan.member) =
  match member.contract.assume_guard.logic.hexpr with
  | HVar name -> name
  | _ -> fail "failed: expected a variable assumption guard"

let member_names members =
  List.map
    (fun (member : Proof_plan.member) -> member.partition_name)
    members

let guard_names members = List.map guard_name members

let expect_individuals name (plan : Proof_plan.t) =
  List.map
    (function
      | Proof_plan.Individual individual -> individual
      | Proof_plan.Grouped _ ->
          fail "failed: %s: expected only individual obligations" name)
    plan.obligations

let expect_only_group name (plan : Proof_plan.t) =
  match plan.obligations with
  | [ Proof_plan.Grouped grouped ] -> grouped
  | obligations ->
      fail "failed: %s: expected one grouped obligation, got %d" name
        (List.length obligations)

let condition_label = function
  | Proof_plan.State_is state -> "state:" ^ state
  | Proof_plan.Formula formula -> (
      match formula.logic.hexpr with
      | HVar name -> "formula:" ^ name
      | HLitBool false -> "formula:false"
      | HLitBool true -> "formula:true"
      | _ -> "formula:other")
  | Proof_plan.Not_formula formula -> (
      match formula.logic.hexpr with
      | HVar name -> "not:" ^ name
      | _ -> "not:other")

let labels conditions = List.map condition_label conditions

let test_policy_decisions () =
  let empty =
    Proof_plan.build_program
      ~policy:{ group_safe_step_contracts = true }
      ~source_model:[ source_node ] ~partition_inputs:[]
  in
  check "no partition produces no plan" (empty = []);
  let first =
    partition "P0"
      [ summary ~step_uid:0 ~assume_guard:"first" () ]
  in
  let second =
    partition "P1"
      [ summary ~step_uid:0 ~assume_guard:"second" () ]
  in
  let disabled = build ~group:false [ first; second ] in
  let disabled_individuals =
    expect_individuals "grouping disabled" disabled
  in
  check "grouping disabled keeps two obligations"
    (List.length disabled_individuals = 2);
  check "grouping disabled preserves indices"
    (List.map
       (fun (individual : Proof_plan.individual) -> individual.index)
       disabled_individuals
    = [ 0; 1 ]);
  check "grouping disabled preserves provenance"
    (List.map
       (fun (individual : Proof_plan.individual) ->
         individual.member.partition_name)
       disabled_individuals
    = [ "P0"; "P1" ]);
  let singleton = build [ first ] in
  check "singleton stays individual"
    (List.length
       (expect_individuals "singleton" singleton)
    = 1);
  let bad_first =
    partition "B0"
      [
        summary ~outcome:Bad_guarantee ~step_uid:0
          ~assume_guard:"bad_first" ();
      ]
  in
  let bad_second =
    partition "B1"
      [
        summary ~outcome:Bad_guarantee ~step_uid:0
          ~assume_guard:"bad_second" ();
      ]
  in
  let bad = build [ bad_first; bad_second ] in
  check "bad guarantees are not grouped"
    (List.length
       (expect_individuals "bad guarantees" bad)
    = 2);
  let grouped = expect_only_group "safe group" (build [ first; second ]) in
  check "safe group starts at first member" (grouped.index = 0);
  check "safe group preserves provenance"
    (member_names grouped.members = [ "P0"; "P1" ]);
  check "safe group preserves member order"
    (guard_names grouped.members = [ "first"; "second" ]);
  check "safe group representative is first"
    (String.equal grouped.representative.partition_name "P0")

let test_partition_order () =
  let first =
    partition "P0"
      [ summary ~step_uid:0 ~assume_guard:"a0" () ]
  in
  let middle =
    partition "P1"
      [
        summary ~program_step:branch ~step_uid:1
          ~assume_guard:"b1" ();
      ]
  in
  let last =
    partition "P2"
      [ summary ~step_uid:0 ~assume_guard:"a2" () ]
  in
  let plan = build [ first; middle; last ] in
  match plan.obligations with
  | [ Proof_plan.Grouped grouped; Proof_plan.Individual individual ] ->
      check "first partition key keeps first index" (grouped.index = 0);
      check "repeated partition key preserves order"
        (member_names grouped.members = [ "P0"; "P2" ]);
      check "repeated partition key preserves contracts"
        (guard_names grouped.members = [ "a0"; "a2" ]);
      check "second partition key keeps original index"
        (individual.index = 1);
      check "second partition key keeps provenance"
        (String.equal individual.member.partition_name "P1")
  | obligations ->
      fail
        "failed: stable partition order: expected grouped then individual, got %d"
        (List.length obligations)

let test_partition_step_class () =
  let safe_first =
    partition "S0"
      [ summary ~step_uid:0 ~assume_guard:"safe_first" () ]
  in
  let bad =
    partition "B1"
      [
        summary ~outcome:Bad_guarantee ~step_uid:0
          ~assume_guard:"bad" ();
      ]
  in
  let safe_last =
    partition "S2"
      [ summary ~step_uid:0 ~assume_guard:"safe_last" () ]
  in
  let plan = build [ safe_first; bad; safe_last ] in
  match plan.obligations with
  | [ Proof_plan.Grouped grouped; Proof_plan.Individual individual ] ->
      check "safe entries stay grouped"
        (member_names grouped.members = [ "S0"; "S2" ]);
      check "bad entry stays separate"
        (individual.member.contract.step_class
        = Step_contract_projection.StepBadGuarantee);
      check "bad entry keeps index" (individual.index = 1)
  | obligations ->
      fail
        "failed: step-class partition: expected grouped then individual, got %d"
        (List.length obligations)

let test_grouped_condition_factoring () =
  let first =
    partition "P0"
      [
        summary ~requires:[ "common"; "left" ]
          ~ensures:[ "post" ] ~step_uid:0
          ~assume_guard:"guard_left" ();
      ]
  in
  let second =
    partition "P1"
      [
        summary ~requires:[ "common"; "right" ]
          ~ensures:[ "post" ] ~step_uid:0
          ~assume_guard:"guard_right" ();
      ]
  in
  let grouped =
    expect_only_group "condition factoring"
      (build [ first; second ])
  in
  check "common conditions are factored canonically"
    (labels grouped.common_preconditions
    = [ "state:S"; "formula:common" ]);
  check "full precondition alternatives are preserved"
    (List.map labels grouped.precondition_alternatives
    =
    [
      [
        "state:S";
        "formula:common";
        "formula:left";
        "formula:guard_left";
      ];
      [
        "state:S";
        "formula:common";
        "formula:right";
        "formula:guard_right";
      ];
    ]);
  match grouped.conditional_posts with
  | [ conditional ] ->
      check "identical conclusions are grouped"
        (labels conditional.conclusions = [ "formula:post" ]);
      check "only residual alternatives remain"
        (List.map labels conditional.alternatives
        =
        [
          [ "formula:left"; "formula:guard_left" ];
          [ "formula:right"; "formula:guard_right" ];
        ])
  | posts ->
      fail
        "failed: condition factoring: expected one conditional post, got %d"
        (List.length posts)

let test_shared_postconditions () =
  let first =
    partition "P0"
      [
        summary ~ensures:[ "post_a"; "post_b" ] ~step_uid:0
          ~assume_guard:"first" ();
      ]
  in
  let second =
    partition "P1"
      [
        summary ~ensures:[ "post_a"; "post_b" ] ~step_uid:1
          ~assume_guard:"second" ();
      ]
  in
  let plan = build ~group:false [ first; second ] in
  let individuals =
    expect_individuals "shared postconditions" plan
  in
  let ids =
    List.map
      (fun (individual : Proof_plan.individual) ->
        individual.shared_postcondition_id)
      individuals
  in
  check "identical postconditions share one identifier"
    (ids = [ Some 1; Some 1 ]);
  match plan.shared_postconditions with
  | [ shared ] ->
      check "shared postcondition identifier is stable"
        (shared.id = 1);
      check "shared postcondition keeps canonical conditions"
        (labels shared.conditions
        = [ "formula:post_a"; "formula:post_b" ])
  | shared ->
      fail
        "failed: shared postconditions: expected one definition, got %d"
        (List.length shared)

let test_signed_condition_sharing () =
  let safe =
    summary ~step_uid:0 ~assume_guard:"safe" ()
    |> fun summary ->
    {
      summary with
      ensures =
        [
          Ir_formula.make (hnot (hvar "p"));
          Ir_formula.make (hnot (hvar "q"));
        ];
    }
  in
  let bad =
    summary ~outcome:Bad_guarantee ~step_uid:1
      ~assume_guard:"bad" ()
    |> fun summary ->
    {
      summary with
      unsafe_cases =
        [
          {
            Ir.product_dst = product_state "S";
            excluded_guard =
              Ir_formula.make (hor (hvar "p") (hvar "q"));
          };
        ];
    }
  in
  let plan =
    build ~group:false
      [ partition "Safe" [ safe ]; partition "Bad" [ bad ] ]
  in
  let ids =
    expect_individuals "signed condition sharing" plan
    |> List.map
         (fun (individual : Proof_plan.individual) ->
           individual.shared_postcondition_id)
  in
  check
    "explicit negative formulas and excluded formulas share one postcondition"
    (ids = [ Some 1; Some 1 ]);
  check "signed sharing emits one definition"
    (List.length plan.shared_postconditions = 1)

let () =
  test_policy_decisions ();
  test_partition_order ();
  test_partition_step_class ();
  test_grouped_condition_factoring ();
  test_shared_postconditions ();
  test_signed_condition_sharing ();
  print_endline "product_group_policy_partition_tests: ok"
