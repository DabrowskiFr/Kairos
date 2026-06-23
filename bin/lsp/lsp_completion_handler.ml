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

let completion oc ~(docs : Lsp_document_store.t) ~id ~params =
  let items =
    match Lsp_text_document_request.document docs params with
    | Some doc ->
        Lsp_completion.completion_items_for_text doc.text
        |> List.map Lsp_completion_view.completion_item_json
    | None -> []
  in
  send_result oc ~id_json:id
    ~result_json:(Lsp_completion_view.completion_list_json items)
