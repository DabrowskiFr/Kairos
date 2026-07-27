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

module Group_partition = Why_compile_product_groups.Group_partition
module Group_policy = Why_compile_product_groups.Group_policy

let fail fmt = Printf.ksprintf (fun msg -> prerr_endline msg; exit 1) fmt

let check name condition = if not condition then fail "failed: %s" name

let expect_decision name expected actual =
  if actual <> expected then
    fail "failed: %s: unexpected grouping decision" name

let product_state label index : Ir.product_state =
  {
    prog_state = label;
    assume_state_index = index;
    guarantee_state_index = index;
  }

let mk_transition src_state dst_state : Ir.transition =
  {
    src_state;
    dst_state;
    guard_expr = None;
    body_stmts = [];
  }

let product_transition ?(step_class = Step_contract_projection.StepSafe)
    ?(transition_id = "tr") ?(src_state = "S") ?(dst_state = "T") () :
    Step_contract_projection.step_contract =
  let program_step = mk_transition src_state dst_state in
  let product_src = product_state src_state 0 in
  let product_dst = product_state dst_state 1 in
  let assume_guard =
    Ir_formula.make
      { Core_syntax.hexpr = Core_syntax.HLitBool true; loc = None }
  in
  {
    transition_id;
    program_transition_id = 0;
    program_step;
    step_class;
    product_src;
    product_dst;
    assume_guard;
    requires = [];
    runtime_requires = [];
    propagates = [];
    ensures = [];
    elaboration_checks = [];
    forbidden = [];
    summary_identity =
      {
        Product_summary_projection.program_transition_id = 0;
        program_step;
        product_src;
        assume_guard = assume_guard.logic;
      };
    covered_cases = [];
  }

let contract ?(step_class = Step_contract_projection.StepSafe)
    ?(transition_id = "tr") () : Step_contract_projection.step_contract =
  product_transition ~step_class ~transition_id ()

let entry ?(step_class = Step_contract_projection.StepSafe)
    ?(product_transition_id = "tr") ?transition index =
  let transition =
    Option.value transition
      ~default:
        (mk_transition "S" "T")
  in
  let contract =
    contract ~step_class ~transition_id:product_transition_id ()
  in
  (index, { contract with program_step = transition })

let ids_of_group group =
  List.map (fun (index, _contract) -> index) group

let test_policy_decisions () =
  let safe_a = entry 0 in
  let safe_b = entry 1 in
  let bad_a =
    entry ~step_class:Step_contract_projection.StepBadGuarantee 2
  in
  let bad_b =
    entry ~step_class:Step_contract_projection.StepBadGuarantee 3
  in
  expect_decision "grouping disabled"
    Group_policy.Individual
    (Group_policy.decide_group ~group_why3_product_steps:false
       [ safe_a; safe_b ]);
  expect_decision "empty group"
    Group_policy.Individual
    (Group_policy.decide_group ~group_why3_product_steps:true []);
  expect_decision "singleton group"
    Group_policy.Individual
    (Group_policy.decide_group ~group_why3_product_steps:true [ safe_a ]);
  expect_decision "non-safe group"
    Group_policy.Individual
    (Group_policy.decide_group ~group_why3_product_steps:true
       [ bad_a; bad_b ]);
  expect_decision "groupable"
    Group_policy.Groupable
    (Group_policy.decide_group ~group_why3_product_steps:true
       [ safe_a; safe_b ])

let test_partition_order () =
  let transition_a = mk_transition "A" "B" in
  let transition_b = mk_transition "A" "C" in
  let groups =
    Group_partition.partition
      [
        entry ~product_transition_id:"p0" ~transition:transition_a 0;
        entry ~product_transition_id:"p1" ~transition:transition_b 1;
        entry ~product_transition_id:"p0" ~transition:transition_a 2;
      ]
  in
  check "partition group count" (List.length groups = 2);
  check "partition first group order" (ids_of_group (List.nth groups 0) = [ 0; 2 ]);
  check "partition second group order" (ids_of_group (List.nth groups 1) = [ 1 ])

let test_partition_step_class () =
  let transition = mk_transition "A" "B" in
  let groups =
    Group_partition.partition
      [
        entry ~step_class:Step_contract_projection.StepSafe ~transition 0;
        entry ~step_class:Step_contract_projection.StepBadGuarantee ~transition
          1;
        entry ~step_class:Step_contract_projection.StepSafe ~transition 2;
      ]
  in
  check "partition separates step class" (List.length groups = 2);
  check "safe entries stay grouped" (ids_of_group (List.nth groups 0) = [ 0; 2 ]);
  check "bad entries stay separate" (ids_of_group (List.nth groups 1) = [ 1 ])

let () =
  test_policy_decisions ();
  test_partition_order ();
  test_partition_step_class ();
  print_endline "product_group_policy_partition_tests: ok"
