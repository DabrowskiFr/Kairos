(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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
 *---------------------------------------------------------------------------*)

open Core_syntax

let fail fmt = Printf.ksprintf (fun msg -> prerr_endline msg; exit 1) fmt
let check name condition = if not condition then fail "failed: %s" name

let historical_true : historical hexpr =
  { hexpr = HLitBool true; loc = None }

let history_free_true : history_free hexpr =
  { hexpr = HLitBool true; loc = None }

let hvar name : history_free hexpr = { hexpr = HVar name; loc = None }

let product_state guarantee_state_index : Ir.product_state =
  {
    prog_state = "S";
    assume_state_index = 0;
    guarantee_state_index;
  }

let loop : Ir.transition =
  {
    src_state = "S";
    dst_state = "S";
    guard_expr = None;
    body_stmts = [];
  }

let model_loop : Verification_model.program_step =
  {
    src_state = "S";
    dst_state = "S";
    guard_expr = None;
    body_stmts = [];
    elaboration_checks = [];
  }

let model_node name : Verification_model.node_model =
  {
    node_name = name;
    type_decls = [];
    function_decls = [];
    inputs = [];
    outputs = [];
    locals = [];
    ghosts = [];
    public_ghosts = [];
    states = [ "S" ];
    init_state = "S";
    steps = [ model_loop ];
    assumes = [];
    guarantees = [];
    state_invariants = [];
  }

let automata : Automaton_types.automata_spec =
  {
    assume_automaton =
      {
        states = [ LTrue ];
        transitions = [ (0, historical_true, 0) ];
      };
    guarantee_automaton =
      {
        states = [ LTrue ];
        transitions = [ (0, historical_true, 0) ];
      };
  }

let safe_case destination : history_free Ir.safe_product_case =
  {
    product_dst = destination;
    admissible_guard = Ir_formula.make history_free_true;
  }

let summary ~step_uid ~source ~destination ~assume_guard :
    history_free Ir.product_step_summary =
  {
    trace = { step_uid };
    identity =
      {
        program_step = loop;
        product_src = source;
        assume_guard = hvar assume_guard;
      };
    propagation_requires = [];
    requires = [];
    ensures = [];
    elaboration_checks = [];
    safe_cases = [ safe_case destination ];
    unsafe_cases = [];
  }

let runtime_node ?(temporal_layout = []) name summaries :
    history_free Ir.node_ir =
  {
    semantics =
      {
        sem_nname = name;
        sem_type_decls = [];
        sem_function_decls = [];
        sem_inputs = [];
        sem_outputs = [];
        sem_locals = [];
        sem_states = [ "S" ];
        sem_init_state = "S";
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout;
    summaries;
    init_invariant_goals = [];
  }

let only name = function
  | [ value ] -> value
  | values ->
      fail "failed: %s: expected one value, got %d" name
        (List.length values)

let check_invalid_arg name expected thunk =
  try
    ignore (thunk ());
    fail "failed: %s: expected Invalid_argument" name
  with
  | Invalid_argument message ->
      check name
        (let message_length = String.length message in
         let expected_length = String.length expected in
         let rec contains offset =
           if offset + expected_length > message_length then false
           else if
             String.sub message offset expected_length = expected
           then true
           else contains (offset + 1)
         in
         expected_length = 0 || contains 0)
  | exn ->
      fail "failed: %s: unexpected exception %s" name
        (Printexc.to_string exn)

let reference_fixture () =
  let source_node =
    {
      (model_node "Source") with
      guarantees =
        [
          Core_syntax.LW (LTrue, LTrue);
          Core_syntax.LW (LTrue, LTrue);
        ];
    }
  in
  let partitioned =
    match
      Contract_partition.partition_program
        ~policy:{ group_public_non_w_guarantees = true }
        [ source_node ]
    with
    | Ok partitioned -> partitioned
    | Error message ->
        fail "failed: contract partition: %s" message
  in
  let first_name, second_name =
    match partitioned.program with
    | [ first; second ] -> (first.node_name, second.node_name)
    | nodes ->
        fail "failed: expected two reference partitions, got %d"
          (List.length nodes)
  in
  let reference_automata =
    [ (first_name, automata); (second_name, automata) ]
  in
  match
    Orchestration.build_reference_product
      {
        reference_program = partitioned.program;
        reference_automata;
        reference_provenance = partitioned.provenance;
      }
  with
  | Ok product ->
      (source_node, product.reference_nodes, first_name, second_name)
  | Error message ->
      fail "failed: reference product: %s" message

let is_false_formula (formula : history_free Ir.summary_formula) =
  match formula.logic.hexpr with HLitBool false -> true | _ -> false

let is_false_condition = function
  | Proof_plan.Formula formula -> is_false_formula formula
  | Proof_plan.State_is _ | Proof_plan.Not_formula _ -> false

let member_has_guard name (member : Proof_plan.member) =
  match member.contract.assume_guard.logic.hexpr with
  | HVar found -> String.equal found name
  | _ -> false

let contract_for_assume_guard name contracts =
  contracts
  |> List.find_opt
       (fun (contract : Step_contract_projection.step_contract) ->
         match contract.assume_guard.logic.hexpr with
         | HVar found -> String.equal found name
         | _ -> false)
  |> function
  | Some contract -> contract
  | None -> fail "failed: missing contract for %s" name

let grouped_for_assume_guard name obligations =
  obligations
  |> List.find_map (function
       | Proof_plan.Grouped grouped
         when List.exists
                (member_has_guard name)
                grouped.members ->
           Some grouped
       | Proof_plan.Individual _ | Proof_plan.Grouped _ -> None)
  |> function
  | Some grouped -> grouped
  | None -> fail "failed: missing grouped obligation for %s" name

let member_for_assume_guard name members =
  members
  |> List.find_opt (member_has_guard name)
  |> function
  | Some member -> member
  | None -> fail "failed: missing planned member for %s" name

let test_proof_plan_preserves_partition_reachability () =
  let source_node, reference_nodes, first_name, second_name =
    reference_fixture ()
  in
  let state0 = product_state 0 in
  let state1 = product_state 1 in
  let first =
    runtime_node first_name
      [
        summary ~step_uid:0 ~source:state0 ~destination:state1
          ~assume_guard:"first_initial";
        summary ~step_uid:1 ~source:state1 ~destination:state1
          ~assume_guard:"first_state_1";
      ]
  in
  let second =
    runtime_node second_name
      [
        summary ~step_uid:0 ~source:state0 ~destination:state0
          ~assume_guard:"second_initial";
        summary ~step_uid:1 ~source:state1 ~destination:state1
          ~assume_guard:"second_state_1";
      ]
  in
  let second_contracts =
    Step_contract_projection.of_ir_node second
  in
  let second_state_before =
    contract_for_assume_guard "second_state_1" second_contracts
  in
  check "second partition state is independently unreachable"
    (List.exists is_false_formula
       second_state_before.runtime_requires);
  let partition_inputs =
    List.map2
      (fun (reference : Orchestration.reference_node) node ->
        ({
           Proof_plan.source_node_name =
             reference.source_node_name;
           node;
         }
          : Proof_plan.partition_input))
      reference_nodes [ first; second ]
  in
  let plan =
    Proof_plan.build_program
      ~policy:{ group_safe_step_contracts = true }
      ~source_model:[ source_node ] ~partition_inputs
    |> only "source proof plan"
  in
  check "plan contains the source signature"
    (String.equal plan.semantics.sem_nname
       source_node.node_name);
  check "plan merges only the temporal layout"
    (plan.temporal_layout = []);
  let grouped =
    grouped_for_assume_guard "second_state_1"
      plan.obligations
  in
  check "group retains both partition members"
    (List.map
       (fun (member : Proof_plan.member) ->
         member.partition_name)
       grouped.members
    = [ first_name; second_name ]);
  check "group retains the product source identity"
    (List.for_all
       (fun (member : Proof_plan.member) ->
         member.contract.product_src = state1)
       grouped.members);
  let second_member =
    member_for_assume_guard "second_state_1"
      grouped.members
  in
  check "planned member keeps unreachable requirement"
    (List.exists is_false_formula
       second_member.contract.runtime_requires);
  let second_index =
    grouped.members
    |> List.mapi (fun index member -> (index, member))
    |> List.find_map (fun (index, member) ->
         if member_has_guard "second_state_1" member then
           Some index
         else None)
    |> function
    | Some index -> index
    | None -> fail "failed: missing second planned member index"
  in
  let second_alternative =
    List.nth grouped.precondition_alternatives
      second_index
  in
  check "planned precondition retains unreachable formula"
    (List.exists is_false_condition second_alternative)

let temporal_info ?(vty = TBool) var_name names :
    Pre_k_layout.pre_k_info =
  { var_name; names; vty }

let test_temporal_layout_merge () =
  let shallow =
    runtime_node
      ~temporal_layout:
        [ temporal_info "x" [ "__pre_k1_x" ] ]
      "P0"
      [
        summary ~step_uid:0 ~source:(product_state 0)
          ~destination:(product_state 0) ~assume_guard:"p0";
      ]
  in
  let deep =
    runtime_node
      ~temporal_layout:
        [
          temporal_info "x"
            [ "__pre_k1_x"; "__pre_k2_x" ];
          temporal_info "y" [ "__pre_k1_y" ];
        ]
      "P1"
      [
        summary ~step_uid:0 ~source:(product_state 0)
          ~destination:(product_state 0) ~assume_guard:"p1";
      ]
  in
  let source = model_node "Source" in
  let input node : Proof_plan.partition_input =
    { source_node_name = "Source"; node }
  in
  let plan =
    Proof_plan.build_program
      ~policy:{ group_safe_step_contracts = true }
      ~source_model:[ source ]
      ~partition_inputs:[ input shallow; input deep ]
    |> only "temporal merge"
  in
  check "temporal merge keeps one entry per variable"
    (List.map
       (fun (info : Pre_k_layout.pre_k_info) ->
         (info.var_name, info.names))
       plan.temporal_layout
    =
    [
      ("x", [ "__pre_k1_x"; "__pre_k2_x" ]);
      ("y", [ "__pre_k1_y" ]);
    ]);
  let wrong_type =
    runtime_node
      ~temporal_layout:
        [ temporal_info ~vty:TInt "x" [ "__pre_k1_x" ] ]
      "Wrong_type"
      [
        summary ~step_uid:0 ~source:(product_state 0)
          ~destination:(product_state 0) ~assume_guard:"wrong_type";
      ]
  in
  check_invalid_arg "temporal type mismatch"
    "incompatible temporal types"
    (fun () ->
      Proof_plan.build_program
        ~policy:{ group_safe_step_contracts = true }
        ~source_model:[ source ]
        ~partition_inputs:[ input shallow; input wrong_type ]);
  let wrong_slots =
    runtime_node
      ~temporal_layout:
        [ temporal_info "x" [ "__other_slot_x" ] ]
      "Wrong_slots"
      [
        summary ~step_uid:0 ~source:(product_state 0)
          ~destination:(product_state 0) ~assume_guard:"wrong_slots";
      ]
  in
  check_invalid_arg "temporal slot mismatch"
    "incompatible temporal slots"
    (fun () ->
      Proof_plan.build_program
        ~policy:{ group_safe_step_contracts = true }
        ~source_model:[ source ]
        ~partition_inputs:[ input shallow; input wrong_slots ])

let test_unknown_partition_source () =
  let node =
    runtime_node "Orphan"
      [
        summary ~step_uid:0 ~source:(product_state 0)
          ~destination:(product_state 0) ~assume_guard:"orphan";
      ]
  in
  check_invalid_arg "unknown partition source"
    "unknown source node Missing"
    (fun () ->
      Proof_plan.build_program
        ~policy:{ group_safe_step_contracts = true }
        ~source_model:[ model_node "Source" ]
        ~partition_inputs:
          [
            ({
               source_node_name = "Missing";
               node;
             }
              : Proof_plan.partition_input);
          ])

let () =
  test_proof_plan_preserves_partition_reachability ();
  test_temporal_layout_merge ();
  test_unknown_partition_source ();
  print_endline
    "proof_plan_partition_tests: partition identity preserved"
