(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module Lsp_types = Lsp.Types

let lsp_location_json = Lsp_location_view.lsp_location_json
let hover_json = Lsp_hover_view.hover_json
let completion_item_json = Lsp_completion_view.completion_item_json
let completion_list_json = Lsp_completion_view.completion_list_json
let full_document_text_edit_json = Lsp_text_edit_view.full_document_text_edit_json
let protocol_request_id = Lsp_request_id_view.protocol_request_id
let send_publish_diagnostics = Lsp_diagnostic_view.send_publish_diagnostics
let parse_diagnostics_for_text = Lsp_diagnostic_view.parse_diagnostics_for_text
let symbol_info = Lsp_symbol_view.symbol_info
