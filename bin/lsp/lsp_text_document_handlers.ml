(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type document_store = Lsp_document_store.t

let did_open = Lsp_document_sync_handlers.did_open
let did_change = Lsp_document_sync_handlers.did_change
let did_save = Lsp_document_sync_handlers.did_save
let did_close = Lsp_document_sync_handlers.did_close
let hover = Lsp_hover_handler.hover
let definition = Lsp_definition_handler.definition
let references = Lsp_references_handler.references
let completion = Lsp_completion_handler.completion
let document_symbol = Lsp_document_symbol_handler.document_symbol
let workspace_symbol = Lsp_workspace_symbol_handler.workspace_symbol
let formatting = Lsp_formatting_handler.formatting
