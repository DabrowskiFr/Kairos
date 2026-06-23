(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** JSON-RPC transport and response helpers for the Kairos LSP executable. *)

module Sync_io : sig
  type 'a t = 'a

  val return : 'a -> 'a
  val raise : exn -> 'a

  module O : sig
    val ( let+ ) : 'a -> ('a -> 'b) -> 'b
    val ( let* ) : 'a -> ('a -> 'b) -> 'b
  end
end

module Channels : sig
  type input = in_channel
  type output = out_channel

  val read_line : input -> string option
  val read_exactly : input -> int -> string option
  val write : output -> string list -> unit
end

module Transport : module type of Lsp.Io.Make (Sync_io) (Channels)

val trace_line : string -> string -> unit
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

val send_work_done_begin :
  out_channel -> token:string -> title:string -> message:string -> unit

val send_work_done_report :
  out_channel -> token:string -> message:string -> unit

val send_work_done_end :
  out_channel -> token:string -> message:string -> unit

val is_request : 'a option -> bool
val id_key : Jsonrpc.Id.t -> string
