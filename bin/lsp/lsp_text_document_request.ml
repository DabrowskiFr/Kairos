(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type document = {
  uri : string;
  text : string;
}

type positioned = {
  uri : string;
  text : string;
  line : int;
  character : int;
}

let document docs params =
  match Lsp_request_decode.get_text_document_uri params with
  | Some uri -> Option.map (fun text -> { uri; text }) (Lsp_document_store.find docs uri)
  | None -> None

let positioned docs params =
  match (document docs params, Lsp_request_decode.position_from_params params) with
  | Some doc, Some (line, character) ->
      Some { uri = doc.uri; text = doc.text; line; character }
  | _ -> None
