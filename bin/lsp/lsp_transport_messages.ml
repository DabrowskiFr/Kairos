(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let send_raw (oc : out_channel) (body : string) : unit =
  output_string oc
    (Printf.sprintf "Content-Length: %d\r\n\r\n%s" (String.length body) body);
  flush oc

let send_packet (oc : out_channel) (packet : Jsonrpc.Packet.t) : unit =
  Lsp_trace.line "lsp-server -> client"
    (Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string);
  Lsp_transport_io.Transport.write oc packet

let error_code_of_int = function
  | -32700 -> Jsonrpc.Response.Error.Code.ParseError
  | -32600 -> Jsonrpc.Response.Error.Code.InvalidRequest
  | -32601 -> Jsonrpc.Response.Error.Code.MethodNotFound
  | -32602 -> Jsonrpc.Response.Error.Code.InvalidParams
  | -32603 -> Jsonrpc.Response.Error.Code.InternalError
  | -32002 -> Jsonrpc.Response.Error.Code.ServerNotInitialized
  | -32800 -> Jsonrpc.Response.Error.Code.RequestCancelled
  | n -> Jsonrpc.Response.Error.Code.Other n

let send_result (oc : out_channel) ~(id_json : Jsonrpc.Id.t)
    ~(result_json : Yojson.Safe.t) : unit =
  send_packet oc (Jsonrpc.Packet.Response (Jsonrpc.Response.ok id_json result_json))

let send_error_raw (oc : out_channel) ~(id_json : Yojson.Safe.t option)
    ~(code : int) ~(message : string) : unit =
  let payload =
    `Assoc
      [
        ("jsonrpc", `String "2.0");
        ("id", Option.value id_json ~default:`Null);
        ("error", `Assoc [ ("code", `Int code); ("message", `String message) ]);
      ]
  in
  Lsp_trace.line "lsp-server -> client" (Yojson.Safe.to_string payload);
  send_raw oc (Yojson.Safe.to_string payload)

let send_error (oc : out_channel) ~(id_json : Jsonrpc.Id.t option)
    ~(code : int) ~(message : string) : unit =
  match id_json with
  | Some id ->
      let error =
        Jsonrpc.Response.Error.make ~code:(error_code_of_int code) ~message ()
      in
      send_packet oc (Jsonrpc.Packet.Response (Jsonrpc.Response.error id error))
  | None -> send_error_raw oc ~id_json:None ~code ~message

let structured_of_json = function
  | (`Assoc _ | `List _) as json -> Some (Jsonrpc.Structured.t_of_yojson json)
  | _ -> None

let send_notification (oc : out_channel) ~(method_name : string)
    ~(params_json : Yojson.Safe.t) : unit =
  let params = structured_of_json params_json in
  send_packet oc
    (Jsonrpc.Packet.Notification
       (Jsonrpc.Notification.create ?params ~method_:method_name ()))

let send_request (oc : out_channel) ~(id_json : Jsonrpc.Id.t)
    ~(method_name : string) ~(params_json : Yojson.Safe.t) : unit =
  let params = structured_of_json params_json in
  send_packet oc
    (Jsonrpc.Packet.Request
       (Jsonrpc.Request.create ?params ~id:id_json ~method_:method_name ()))
