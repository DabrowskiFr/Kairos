(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let read_packet ~input ~output =
  try Lsp_transport.Transport.read input
  with _ ->
    Lsp_transport.send_error_raw output ~id_json:None ~code:(-32700)
      ~message:"Parse error";
    None

let run ~input ~output =
  let state = Lsp_server_state.create () in
  while !(state.running) do
    match read_packet ~input ~output with
    | None -> state.running := false
    | Some packet -> Lsp_packet_handler.handle output state packet
  done
