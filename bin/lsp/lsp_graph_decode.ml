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

let dot_text params =
  match decode_or_none Lsp_protocol.dot_png_from_text_request_of_yojson params with
  | Some req -> Some req.dot_text
  | None -> Lsp_request_decode.get_param_string params "dotText"
