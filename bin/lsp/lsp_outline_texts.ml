(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type t = {
  source_text : string;
  abstract_text : string;
}

let resolve ~(docs : Lsp_document_store.t) (req : Lsp_outline_decode.t) =
  let source_text =
    match (req.source_text, req.uri) with
    | Some text, _ -> text
    | None, Some uri -> Option.value (Lsp_document_store.find docs uri) ~default:""
    | None, None -> ""
  in
  let abstract_text = Option.value req.abstract_text ~default:"" in
  { source_text; abstract_text }
