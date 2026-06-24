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
  cfg : Pipeline_types.config;
  engine : Engine_service.engine;
  input_file : string;
}

let pipeline_config_of_protocol = Lsp_backend_config.pipeline_config_of_protocol

let config_from_compat_params ~input_file params =
  {
    Pipeline_types.input_file;
    wp_only = Lsp_request_decode.get_param_bool params "wpOnly" false;
    smoke_tests = Lsp_request_decode.get_param_bool params "smokeTests" false;
    timeout_s = Lsp_request_decode.get_param_int params "timeoutS" 5;
    compute_proof_diagnostics =
      Lsp_request_decode.get_param_bool params "computeProofDiagnostics" false;
    prove = Lsp_request_decode.get_param_bool params "prove" true;
    proof_jobs =
      Lsp_request_decode.get_param_int params "proofJobs"
        Pipeline_types.default_proof_jobs;
    generate_why_text =
      not (Lsp_request_decode.get_param_bool params "prove" true);
    generate_vc_text =
      Lsp_request_decode.get_param_bool params "generateVcText" false;
    generate_smt_text =
      Lsp_request_decode.get_param_bool params "generateSmtText" false;
    generate_dot_png =
      Lsp_request_decode.get_param_bool params "generateDotPng" false;
    dump_failed_smt = false;
    collect_ir_metrics = false;
    proof_progress_path = None;
    stop_on_first_nonvalid = false;
    proof_encoding = Pipeline_types.default_proof_encoding;
    proof_optimizations = Pipeline_types.default_proof_optimizations;
  }

let lsp_config_of_pipeline ~engine (cfg : Pipeline_types.config) :
    Lsp_protocol.config =
  {
    Lsp_protocol.input_file = cfg.input_file;
    engine = Engine_service.string_of_engine engine;
    wp_only = cfg.wp_only;
    smoke_tests = cfg.smoke_tests;
    timeout_s = cfg.timeout_s;
    compute_proof_diagnostics = cfg.compute_proof_diagnostics;
    prove = cfg.prove;
    proof_jobs = cfg.proof_jobs;
    generate_vc_text = cfg.generate_vc_text;
    generate_smt_text = cfg.generate_smt_text;
    generate_dot_png = cfg.generate_dot_png;
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
        | Some cfg ->
            let cfg = pipeline_config_of_protocol cfg in
            { cfg with input_file }
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
  lsp_config_of_pipeline ~engine:decoded.engine decoded.cfg
