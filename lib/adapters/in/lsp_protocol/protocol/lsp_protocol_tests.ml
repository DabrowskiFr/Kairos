let fail message =
  prerr_endline ("lsp_protocol_tests: " ^ message);
  exit 1

let base_config_json =
  `Assoc
    [
      ("input_file", `String "program.kairos");
      ("engine", `String "default");
      ("wp_only", `Bool false);
      ("smoke_tests", `Bool false);
      ("timeout_s", `Int 5);
      ("compute_proof_diagnostics", `Bool false);
      ("prove", `Bool true);
      ("generate_vc_text", `Bool false);
      ("generate_smt_text", `Bool false);
      ("generate_dot_png", `Bool false);
    ]

let () =
  let decoded =
    match Lsp_protocol.config_of_yojson base_config_json with
    | Ok config -> config
    | Error message -> fail ("could not decode config: " ^ message)
  in
  if decoded.proof_jobs <> None then
    fail "an omitted proof_jobs field must remain absent for the engine default";
  let configured = { decoded with proof_jobs = Some 3 } in
  match
    Lsp_protocol.config_of_yojson
      (Lsp_protocol.yojson_of_config configured)
  with
  | Ok roundtrip when roundtrip.proof_jobs = Some 3 -> ()
  | Ok _ -> fail "proof_jobs was not preserved by the JSON round trip"
  | Error message -> fail ("round-trip decode failed: " ^ message)
