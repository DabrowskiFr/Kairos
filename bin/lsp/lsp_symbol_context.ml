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
  uri : string;
  text : string;
  ident : string;
  symbols : Lsp_symbols.semantic_symbols;
}

let resolve (docs : Lsp_document_store.t) params =
  match Lsp_text_document_request.positioned docs params with
  | Some doc -> (
      match
        ( Lsp_symbols.identifier_at doc.text doc.line doc.character,
          Lsp_symbols.semantic_symbols_for_text doc.text )
      with
      | Some ident, Some symbols ->
          Some { uri = doc.uri; text = doc.text; ident; symbols }
      | _ -> None)
  | None -> None
