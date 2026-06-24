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

module Group_partition = Why_compile_product_group_partition
module Group_policy = Why_compile_product_group_policy

let fail fmt = Printf.ksprintf (fun msg -> prerr_endline msg; exit 1) fmt

let check name condition = if not condition then fail "failed: %s" name

let expect_decision name expected actual =
  if actual <> expected then
    fail "failed: %s: unexpected grouping decision" name

let true_term = Why_compile_expr.mk_term Why3.Ptree.Ttrue

let product_state label index : Ir.product_state =
  {
    prog_state = label;
    assume_state_index = index;
    guarantee_state_index = index;
  }

let runtime_transition transition_id src_state dst_state :
    Why_runtime_view.runtime_transition_view =
  {
    transition_id;
    src_state;
    dst_state;
    guard = None;
    requires = [];
    ensures = [];
    body = [];
    action_blocks = [];
  }

let product_transition ?(step_class = Why_runtime_view.StepSafe)
    ?(transition_id = "tr") ?(src_state = "S") ?(dst_state = "T") () :
    Why_runtime_view.runtime_product_transition_view =
  {
    transition_id;
    src_state;
    dst_state;
    guard = None;
    body = [];
    step_class;
    product_src = product_state src_state 0;
    product_dst = product_state dst_state 1;
    requires = [];
    local_requires = [];
    propagates = [];
    ensures = [];
    forbidden = [];
  }

let contract ?(step_class = Why_runtime_view.StepSafe) ?(local_cuts = [])
    ?(transition_id = "tr") () : Why_contracts.step_contract_info =
  {
    step = product_transition ~step_class ~transition_id ();
    pre = [];
    pre_labels = [];
    post = [];
    post_labels = [];
    local_cuts;
    forbidden = [];
    forbidden_labels = [];
  }

let entry ?(step_class = Why_runtime_view.StepSafe) ?(local_cuts = [])
    ?(product_transition_id = "tr") ?transition index =
  let transition =
    Option.value transition
      ~default:
        (runtime_transition
           ("runtime_" ^ string_of_int index)
           "S" "T")
  in
  ( index,
    contract ~step_class ~local_cuts ~transition_id:product_transition_id (),
    transition )

let ids_of_group group =
  Group_partition.entries group |> List.map (fun (index, _contract, _t) -> index)

let test_policy_decisions () =
  let safe_a = entry 0 in
  let safe_b = entry 1 in
  let bad_a = entry ~step_class:Why_runtime_view.StepBadGuarantee 2 in
  let bad_b = entry ~step_class:Why_runtime_view.StepBadGuarantee 3 in
  let cut_a = entry ~local_cuts:[ true_term ] 4 in
  let cut_b = entry 5 in
  expect_decision "grouping disabled"
    (Group_policy.Individual Group_policy.Grouping_disabled)
    (Group_policy.decide_group ~group_why3_product_steps:false
       [ safe_a; safe_b ]);
  expect_decision "empty group"
    (Group_policy.Individual Group_policy.Empty_group)
    (Group_policy.decide_group ~group_why3_product_steps:true []);
  expect_decision "singleton group"
    (Group_policy.Individual Group_policy.Singleton_group)
    (Group_policy.decide_group ~group_why3_product_steps:true [ safe_a ]);
  expect_decision "non-safe group"
    (Group_policy.Individual Group_policy.Non_safe_step)
    (Group_policy.decide_group ~group_why3_product_steps:true
       [ bad_a; bad_b ]);
  expect_decision "local cuts"
    (Group_policy.Individual Group_policy.Has_local_cuts)
    (Group_policy.decide_group ~group_why3_product_steps:true [ cut_a; cut_b ]);
  expect_decision "groupable"
    Group_policy.Groupable
    (Group_policy.decide_group ~group_why3_product_steps:true
       [ safe_a; safe_b ]);
  check "stable reason name"
    (Group_policy.individual_reason_name Group_policy.Split_singleton
    = "split_singleton")

let test_partition_order () =
  let transition_a = runtime_transition "runtime_a" "A" "B" in
  let transition_b = runtime_transition "runtime_b" "A" "C" in
  let groups =
    Group_partition.partition
      [
        entry ~product_transition_id:"p0" ~transition:transition_a 0;
        entry ~product_transition_id:"p1" ~transition:transition_b 1;
        entry ~product_transition_id:"p2" ~transition:transition_a 2;
      ]
  in
  check "partition group count" (List.length groups = 2);
  check "partition first group order" (ids_of_group (List.nth groups 0) = [ 0; 2 ]);
  check "partition second group order" (ids_of_group (List.nth groups 1) = [ 1 ])

let test_partition_step_class () =
  let transition = runtime_transition "runtime_shared" "A" "B" in
  let groups =
    Group_partition.partition
      [
        entry ~step_class:Why_runtime_view.StepSafe ~transition 0;
        entry ~step_class:Why_runtime_view.StepBadGuarantee ~transition 1;
        entry ~step_class:Why_runtime_view.StepSafe ~transition 2;
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
