let fail message =
  prerr_endline ("lsp_protocol_tests: " ^ message);
  exit 1

let base_config_json =
  `Assoc
    [
      ("input_file", `String "program.kairos");
      ("engine", `String "default");
      ("wp_only", `Bool false);
      ("timeout_s", `Int 5);
      ("compute_proof_diagnostics", `Bool false);
      ("prove", `Bool true);
      ("generate_vc_text", `Bool false);
      ("generate_smt_text", `Bool false);
      ("generate_dot_png", `Bool false);
    ]

let () =
  let decoded =
    match Kr_lsp_protocol.config_of_yojson base_config_json with
    | Ok config -> config
    | Error message -> fail ("could not decode config: " ^ message)
  in
  if decoded.proof_jobs <> None then
    fail "an omitted proof_jobs field must remain absent for the engine default";
  let configured = { decoded with proof_jobs = Some 3 } in
  match
    Kr_lsp_protocol.config_of_yojson
      (Kr_lsp_protocol.yojson_of_config configured)
  with
  | Ok roundtrip when roundtrip.proof_jobs = Some 3 -> ()
  | Ok _ -> fail "proof_jobs was not preserved by the JSON round trip"
  | Error message -> fail ("round-trip decode failed: " ^ message)

let empty_diagnostic : Kr_lsp_protocol.proof_diagnostic =
  {
    category = "";
    summary = "";
    detail = "";
    probable_cause = None;
    missing_elements = [];
    goal_symbols = [];
    analysis_method = "";
    solver_detail = None;
    native_unsat_core_solver = None;
    native_unsat_core_hypothesis_ids = [];
    native_counterexample_solver = None;
    native_counterexample_model = None;
    kr_core_hypotheses = [];
    why3_noise_hypotheses = [];
    relevant_hypotheses = [];
    context_hypotheses = [];
    unused_hypotheses = [];
    suggestions = [];
    limitations = [];
  }

let () =
  let trace : Kr_lsp_protocol.proof_trace =
    {
      goal_index = 0;
      stable_id = "vc-001";
      goal_name = "__kairos_proof_unit_node_transition_group_2";
      status = "valid";
      solver_status = "valid";
      time_s = 0.0;
      source = "";
      node = Some "node";
      transition = Some "transition";
      obligation_kind = "product-step";
      obligation_family = Some "product-step-group";
      obligation_category = None;
      canonical_obligation_ids = [ 2; 7 ];
      vc_id = Some "1";
      source_span = None;
      why_span = None;
      vc_span = None;
      smt_span = None;
      dump_path = None;
      diagnostic = empty_diagnostic;
    }
  in
  let json = Kr_lsp_protocol.yojson_of_proof_trace trace in
  let encoded_ids =
    match json with
    | `Assoc fields ->
        List.assoc_opt "canonical_obligation_ids" fields
    | _ -> None
  in
  if encoded_ids <> Some (`List [ `Int 2; `Int 7 ]) then
    fail "canonical obligation ids were not encoded as a JSON array";
  match Kr_lsp_protocol.proof_trace_of_yojson json with
  | Ok decoded
    when decoded.canonical_obligation_ids = trace.canonical_obligation_ids ->
      ()
  | Ok _ ->
      fail
        "canonical obligation ids were not preserved by the JSON round trip"
  | Error message ->
      fail ("proof-trace round-trip decode failed: " ^ message)
