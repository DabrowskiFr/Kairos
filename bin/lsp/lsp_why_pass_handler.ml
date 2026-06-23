(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

open Lsp_transport

let why_pass oc ~id ~params =
  match Lsp_pipeline_pass_decode.why_pass params with
  | Some req when Lsp_pipeline_pass_input.valid_file req.input_file -> (
      match Lsp_backend_usecases.why_pass req with
      | Ok out ->
          send_result oc ~id_json:id
            ~result_json:(Lsp_protocol.yojson_of_why_outputs out)
      | Error msg ->
          send_error oc ~id_json:(Some id) ~code:(-32001) ~message:msg)
  | _ ->
      Lsp_pipeline_pass_input.reject_missing_input_file oc ~id
        ~message:"Missing valid inputFile"
