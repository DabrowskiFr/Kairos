(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

let pipeline_config_of_protocol =
  Lsp_backend_config.pipeline_config_of_protocol

let instrumentation_pass = Lsp_backend_usecases.instrumentation_pass
let why_pass = Lsp_backend_usecases.why_pass
let obligations_pass = Lsp_backend_usecases.obligations_pass
let normalized_program = Lsp_backend_usecases.normalized_program
let ir_pretty_dump = Lsp_backend_usecases.ir_pretty_dump
let dot_png_from_text = Lsp_backend_graph.dot_png_from_text
let run = Lsp_backend_usecases.run
let run_with_callbacks = Lsp_backend_usecases.run_with_callbacks
