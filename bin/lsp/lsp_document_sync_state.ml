(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let apply_text_update docs (update : Lsp_document_sync_decode.text_update) =
  Lsp_document_store.replace docs update.uri update.text;
  update.text

let text_for_save docs uri =
  Option.value (Lsp_document_store.find docs uri) ~default:""

let close docs uri = Lsp_document_store.remove docs uri
