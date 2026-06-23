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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module Sync_io = Lsp_transport_io.Sync_io
module Channels = Lsp_transport_io.Channels
module Transport = Lsp_transport_io.Transport

let trace_line = Lsp_trace.line
let send_raw = Lsp_transport_messages.send_raw
let send_packet = Lsp_transport_messages.send_packet
let send_result = Lsp_transport_messages.send_result
let send_error_raw = Lsp_transport_messages.send_error_raw
let send_error = Lsp_transport_messages.send_error
let send_notification = Lsp_transport_messages.send_notification
let send_request = Lsp_transport_messages.send_request
let send_work_done_begin = Lsp_work_done_transport.send_begin
let send_work_done_report = Lsp_work_done_transport.send_report
let send_work_done_end = Lsp_work_done_transport.send_end
let is_request = Lsp_jsonrpc_id.is_request
let id_key = Lsp_jsonrpc_id.key
