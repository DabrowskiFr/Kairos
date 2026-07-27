open Core_syntax
open Core_syntax_builders

let fail message =
  prerr_endline message;
  exit 1

let formula logic = Ir_formula.make logic

let () =
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
