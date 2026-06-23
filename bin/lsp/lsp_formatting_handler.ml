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

let formatting oc ~(docs : Lsp_document_store.t) ~id ~params =
  let edits =
    match Lsp_text_document_request.document docs params with
    | Some doc ->
        let lines = String.split_on_char '\n' doc.text in
        let line_count = max 1 (List.length lines) in
        let new_text = Lsp_formatting.format_text doc.text in
        if new_text = doc.text then []
        else [ Lsp_text_edit_view.full_document_text_edit_json ~line_count ~new_text ]
    | None -> []
  in
  send_result oc ~id_json:id ~result_json:(`List edits)
