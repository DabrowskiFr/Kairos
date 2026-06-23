(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let publish_update oc docs update =
  let text = Lsp_document_sync_state.apply_text_update docs update in
  Lsp_document_diagnostics.publish_text oc ~uri:update.uri ~text

let did_open oc ~(docs : Lsp_document_store.t) ~params =
  Option.iter (publish_update oc docs) (Lsp_document_sync_decode.did_open params)

let did_change oc ~(docs : Lsp_document_store.t) ~params =
  Option.iter
    (publish_update oc docs)
    (Lsp_document_sync_decode.did_change params)

let did_save oc ~(docs : Lsp_document_store.t) ~params =
  match Lsp_document_sync_decode.document_uri params with
  | Some uri ->
      let text = Lsp_document_sync_state.text_for_save docs uri in
      Lsp_document_diagnostics.publish_text oc ~uri ~text
  | None -> ()

let did_close oc ~(docs : Lsp_document_store.t) ~params =
  match Lsp_document_sync_decode.document_uri params with
  | Some uri ->
      Lsp_document_sync_state.close docs uri;
      Lsp_document_diagnostics.publish_clear oc ~uri
  | None -> ()
