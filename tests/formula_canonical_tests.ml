open Core_syntax
open Core_syntax_builders

let fail message =
  prerr_endline message;
  exit 1

let formula logic = Ir_formula.make logic

let sharing_characterization_node () :
    Core_syntax.historical Ir.node_ir =
  let product_state : Ir.product_state =
    {
      prog_state = "S";
      assume_state_index = 0;
      guarantee_state_index = 0;
    }
  in
  let program_step : Ir.transition =
    {
      src_state = "S";
      dst_state = "S";
      guard_expr = None;
      body_stmts = [];
    }
  in
  let shared () = mk_hvar "shared" in
  let simplifies_to_shared () = mk_hand (mk_hbool true) (shared ()) in
  let span : Loc.loc = { line = 1; col = 0; line_end = 1; col_end = 6 } in
  let located () = mk_hexpr ~loc:span (HVar "located") in
  let located_simplifies_to_shared () =
    mk_hexpr ~loc:span (HBin (And, mk_hbool true, shared ()))
  in
  let summary : Core_syntax.historical Ir.product_step_summary =
    {
      trace = { step_uid = 0 };
      identity =
        {
          program_step;
          product_src = product_state;
          assume_guard = shared ();
        };
      propagation_requires =
        [
          formula (simplifies_to_shared ());
          formula (located_simplifies_to_shared ());
        ];
      requires = [ formula (shared ()) ];
      ensures = [ formula (shared ()) ];
      elaboration_checks = [ formula (located ()) ];
      safe_cases =
        [
          {
            product_dst = product_state;
            admissible_guard = formula (shared ());
          };
        ];
      unsafe_cases =
        [
          {
            product_dst = product_state;
            excluded_guard = formula (located ());
          };
        ];
    }
  in
  {
    semantics =
      {
        sem_nname = "sharing";
        sem_type_decls = [];
        sem_function_decls = [];
        sem_inputs = [];
        sem_outputs = [];
        sem_locals = [];
        sem_states = [ "S" ];
        sem_init_state = "S";
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout = [];
    summaries = [ summary ];
    init_invariant_goals = [ formula (shared ()) ];
  }

let formula_payloads (node : Core_syntax.history_free Ir.node_ir) =
  match node.summaries with
  | [ summary ] ->
      [
        summary.identity.assume_guard;
        (List.hd summary.propagation_requires).logic;
        (List.nth summary.propagation_requires 1).logic;
        (List.hd summary.requires).logic;
        (List.hd summary.ensures).logic;
        (List.hd summary.elaboration_checks).logic;
        (List.hd summary.safe_cases).admissible_guard.logic;
        (List.hd summary.unsafe_cases).excluded_guard.logic;
        (List.hd node.init_invariant_goals).logic;
      ]
  | _ -> fail "temporal_lower sharing fixture has an invalid summary count"

let test_temporal_lower_owns_physical_sharing () =
  let lowered =
    Temporal_lower.run_program [ sharing_characterization_node () ]
    |> List.hd
  in
  let payloads = formula_payloads lowered in
  let unlocated =
    List.filter
      (fun (formula : Core_syntax.history_free Core_syntax.hexpr) ->
        formula.loc = None)
      payloads
  in
  (match unlocated with
  | representative :: rest ->
      if List.exists (fun formula -> formula != representative) rest then
        fail
          "temporal_lower: equal location-free results are not physically \
           shared"
  | [] -> fail "temporal_lower sharing fixture has no location-free formula");
  let located =
    List.filter
      (fun (formula : Core_syntax.history_free Core_syntax.hexpr) ->
        formula.loc <> None)
      payloads
  in
  (match located with
  | [ first; second ] when first != second -> ()
  | _ ->
      fail
        "temporal_lower: located formulas must retain distinct representatives")

let () =
  test_temporal_lower_owns_physical_sharing ();
  let x = mk_hvar "x" in
  let y = mk_hvar "y" in
  let conjunction = mk_hand x y in
  let conjunction_copy = mk_hand (mk_hvar "x") (mk_hvar "y") in
  let pool = Formula_canonical.create_pool () in
  let first = Formula_canonical.intern pool conjunction in
  let second = Formula_canonical.intern pool conjunction_copy in
  if first != second then
    fail "formula_canonical: equal formulas were not physically shared";

  let normalized_pool = Formula_canonical.create_pool () in
  let noisy = mk_hand (mk_hbool true) x in
  let normalized =
    Formula_canonical.intern ~normalize:Core_fo_simplifier.simplify
      normalized_pool noisy
  in
  let direct =
    Formula_canonical.intern ~normalize:Core_fo_simplifier.simplify
      normalized_pool x
  in
  if normalized != direct then
    fail "formula_canonical: normalization policy was not applied";

  let free_x : history_free hexpr = mk_hvar "x" in
  let free_conjunction : history_free hexpr =
    mk_hand free_x (mk_hvar "y")
  in
  let free_conjunction_copy : history_free hexpr =
    mk_hand (mk_hvar "x") (mk_hvar "y")
  in
  let indexed_conjunction = formula free_conjunction in
  let indexed_conjunction_copy = formula free_conjunction_copy in
  let indexed_conjunction_copy_again = formula free_conjunction_copy in
  let indexed_atomic = formula free_x in
  let index =
    Contract_formula_index.build
      [
        [ indexed_conjunction; indexed_conjunction_copy ];
        [ indexed_conjunction_copy_again; indexed_atomic ];
      ]
  in
  let definitions = Contract_formula_index.definitions index in
  if List.length definitions <> 1 then
    fail
      "contract_formula_index: expected one composite formula reused by two \
       contracts";
  let definition = List.hd definitions in
  if definition.id <> 0 then
    fail "contract_formula_index: definition numbering changed";
  if Contract_formula_index.find index indexed_conjunction = None then
    fail "contract_formula_index: repeated composite formula was not indexed";
  if
    Contract_formula_index.find index indexed_conjunction_copy
    <> Some definition
    || Contract_formula_index.find index indexed_conjunction_copy_again
       <> Some definition
  then
    fail
      "contract_formula_index: equivalent indexed occurrences do not resolve \
       to the same definition";
  if Contract_formula_index.find index indexed_atomic <> None then
    fail "contract_formula_index: atomic formula must remain inline";
  if
    Contract_formula_index.find index (formula free_conjunction)
    <> None
  then
    fail
      "contract_formula_index: an occurrence absent from the index must remain \
       inline";

  let conflicting =
    {
      indexed_conjunction with
      logic = mk_hbool false;
    }
  in
  (match
     Contract_formula_index.build
       [ [ indexed_conjunction ]; [ conflicting ] ]
   with
  | _ ->
      fail
        "contract_formula_index: conflicting reuse of an oid was not rejected"
  | exception Invalid_argument _ -> ());
  print_endline "formula_canonical_tests: ok"
