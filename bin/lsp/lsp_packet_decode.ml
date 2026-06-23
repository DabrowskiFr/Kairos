(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type t =
  | Ignore
  | Unsupported_batch_call
  | Call of Lsp_call.t

let params_json = function
  | None -> `Assoc []
  | Some p -> (p :> Yojson.Safe.t)

let of_packet packet =
  match packet with
  | Jsonrpc.Packet.Response _ | Jsonrpc.Packet.Batch_response _ -> Ignore
  | Jsonrpc.Packet.Batch_call _ -> Unsupported_batch_call
  | Jsonrpc.Packet.Request req ->
      Lsp_packet_trace.client_packet packet;
      Call
        {
          method_name = Some req.method_;
          id_json = Some req.id;
          params = params_json req.params;
        }
  | Jsonrpc.Packet.Notification notif ->
      Lsp_packet_trace.client_packet packet;
      Call
        {
          method_name = Some notif.method_;
          id_json = None;
          params = params_json notif.params;
        }
