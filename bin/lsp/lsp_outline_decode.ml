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

type t = {
  uri : string option;
  source_text : string option;
  abstract_text : string option;
}

let of_params params =
  match decode_or_none Lsp_protocol.outline_request_of_yojson params with
  | Some req ->
      {
        uri = req.uri;
        source_text = req.source_text;
        abstract_text = req.abstract_text;
      }
  | None ->
      {
        uri = Lsp_request_decode.get_param_string params "uri";
        source_text = Lsp_request_decode.get_param_string params "sourceText";
        abstract_text =
          Lsp_request_decode.get_param_string params "abstractText";
      }
