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

let instrumentation_pass params =
  match
    decode_or_none Lsp_protocol.instrumentation_pass_request_of_yojson params
  with
  | Some req -> Some req
  | None -> (
      match Lsp_request_decode.get_param_string params "inputFile" with
      | Some input_file ->
          Some
            {
              Lsp_protocol.input_file;
              generate_png =
                Lsp_request_decode.get_param_bool params "generatePng" true;
              engine = Engine_service.string_of_engine (get_engine params);
            }
      | None -> None)

let why_pass params =
  match decode_or_none Lsp_protocol.why_pass_request_of_yojson params with
  | Some req -> Some req
  | None -> (
      match Lsp_request_decode.get_param_string params "inputFile" with
      | Some input_file ->
          Some
            {
              Lsp_protocol.input_file;
              engine = Engine_service.string_of_engine (get_engine params);
            }
      | None -> None)

let obligations_pass params =
  match decode_or_none Lsp_protocol.obligations_pass_request_of_yojson params with
  | Some req -> Some req
  | None -> (
      match Lsp_request_decode.get_param_string params "inputFile" with
      | Some input_file ->
          Some
            {
              Lsp_protocol.input_file;
              engine = Engine_service.string_of_engine (get_engine params);
            }
      | _ -> None)
