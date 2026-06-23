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

let document_symbol oc ~(docs : Lsp_document_store.t) ~id ~params =
  let symbols =
    match Lsp_text_document_request.document docs params with
    | Some doc ->
        Lsp_symbols.document_symbols_for_text doc.text
        |> List.map (fun symbol ->
               Lsp_symbol_view.symbol_info ~uri:doc.uri
                 ~name:symbol.Lsp_symbols.name ~line:symbol.line
                 ~character:symbol.character)
    | None -> []
  in
  send_result oc ~id_json:id ~result_json:(`List symbols)
