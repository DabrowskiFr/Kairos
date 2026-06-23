(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** JSON-RPC message emission helpers. *)

val send_raw : out_channel -> string -> unit
val send_packet : out_channel -> Jsonrpc.Packet.t -> unit
val send_result : out_channel -> id_json:Jsonrpc.Id.t -> result_json:Yojson.Safe.t -> unit

val send_error_raw :
  out_channel ->
  id_json:Yojson.Safe.t option ->
  code:int ->
  message:string ->
  unit

val send_error :
  out_channel ->
  id_json:Jsonrpc.Id.t option ->
  code:int ->
  message:string ->
  unit

val send_notification :
  out_channel ->
  method_name:string ->
  params_json:Yojson.Safe.t ->
  unit

val send_request :
  out_channel ->
  id_json:Jsonrpc.Id.t ->
  method_name:string ->
  params_json:Yojson.Safe.t ->
  unit
