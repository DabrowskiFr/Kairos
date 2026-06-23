(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type text_update = {
  uri : string;
  text : string;
}

let text_update uri text =
  match (uri, text) with
  | Some uri, Some text -> Some { uri; text }
  | _ -> None

let did_open params =
  text_update
    (Lsp_request_decode.get_text_document_uri params)
    (Lsp_request_decode.get_did_open_text params)

let did_change params =
  text_update
    (Lsp_request_decode.get_text_document_uri params)
    (Lsp_request_decode.get_did_change_text params)

let document_uri params = Lsp_request_decode.get_text_document_uri params
