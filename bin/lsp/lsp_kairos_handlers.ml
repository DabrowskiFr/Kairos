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

let outline = Lsp_outline_request_handler.outline
let goals_tree_final = Lsp_goal_tree_final_handler.goals_tree_final
let goals_tree_pending = Lsp_goal_tree_pending_handler.goals_tree_pending
let instrumentation_pass = Lsp_instrumentation_pass_handler.instrumentation_pass
let why_pass = Lsp_why_pass_handler.why_pass
let obligations_pass = Lsp_obligations_pass_handler.obligations_pass
let dot_png_from_text = Lsp_graph_handler.dot_png_from_text
