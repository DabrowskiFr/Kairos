module Contract = Kr_why3_contract.Why3_contract

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "failed: %s" label
let require_ok label = function Ok value -> value | Error message -> fail "%s: %s" label message

let () =
  let options : Contract.execution_options =
    {
      timeout_s = 5;
      jobs = 2;
      split_vc = true;
      dump_failed_smt = false;
      prove = true;
      emit_vc_text = true;
      emit_smt_text = true;
      diagnose_nonvalid = false;
    }
  in
  require_ok "valid execution options" (Contract.validate_execution_options options);
  check "non-positive worker count rejected"
    (Result.is_error (Contract.validate_execution_options { options with jobs = 0 }));
  print_endline "why3_contract_tests: ok"
