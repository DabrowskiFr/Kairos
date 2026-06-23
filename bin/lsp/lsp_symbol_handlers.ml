(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let hover = Lsp_hover_handler.hover
let definition = Lsp_definition_handler.definition
let references = Lsp_references_handler.references
let document_symbol = Lsp_document_symbol_handler.document_symbol
let workspace_symbol = Lsp_workspace_symbol_handler.workspace_symbol
