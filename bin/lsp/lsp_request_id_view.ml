(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let protocol_request_id (id : Jsonrpc.Id.t) : Lsp_protocol.rpc_request_id =
  match Lsp_protocol.rpc_request_id_of_yojson (Jsonrpc.Id.yojson_of_t id) with
  | Ok request_id -> request_id
  | Error _ ->
      Lsp_protocol.Rpc_string_id
        (Jsonrpc.Id.yojson_of_t id |> Yojson.Safe.to_string)
