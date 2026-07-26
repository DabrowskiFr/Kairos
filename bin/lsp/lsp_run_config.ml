(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

open Lsp_request_helpers

type decoded = {
  cfg : Lsp_protocol.config;
  engine : Engine_service.engine;
  input_file : string;
}

let config_from_compat_params ~input_file params =
  {
    Lsp_protocol.input_file;
    engine =
      Option.value
        (Lsp_request_decode.get_param_string params "engine")
        ~default:"default";
    wp_only = Lsp_request_decode.get_param_bool params "wpOnly" false;
    smoke_tests = Lsp_request_decode.get_param_bool params "smokeTests" false;
    timeout_s = Lsp_request_decode.get_param_int params "timeoutS" 5;
    compute_proof_diagnostics =
      Lsp_request_decode.get_param_bool params "computeProofDiagnostics" false;
    prove = Lsp_request_decode.get_param_bool params "prove" true;
    proof_jobs =
      Some
        (Lsp_request_decode.get_param_int params "proofJobs"
           (Kairos_engine.Api.default_proof_jobs ()));
    generate_vc_text =
      Lsp_request_decode.get_param_bool params "generateVcText" false;
    generate_smt_text =
      Lsp_request_decode.get_param_bool params "generateSmtText" false;
    generate_dot_png =
      Lsp_request_decode.get_param_bool params "generateDotPng" false;
  }

let decode (params : Yojson.Safe.t) : decoded option =
  let cfg_from_protocol = decode_or_none Lsp_protocol.config_of_yojson params in
  let input_file =
    match cfg_from_protocol with
    | Some cfg -> Some cfg.input_file
    | None -> Lsp_request_decode.get_param_string params "inputFile"
  in
  match input_file with
  | None -> None
  | Some input_file ->
      let cfg =
        match cfg_from_protocol with
        | Some cfg -> { cfg with input_file }
        | None -> config_from_compat_params ~input_file params
      in
      let engine =
        match cfg_from_protocol with
        | Some cfg ->
            Option.value (Engine_service.engine_of_string cfg.engine)
              ~default:Engine_service.Default
        | None -> get_engine params
      in
      Some { cfg; engine; input_file }

let lsp_config decoded =
  {
    decoded.cfg with
    engine = Engine_service.string_of_engine decoded.engine;
  }
