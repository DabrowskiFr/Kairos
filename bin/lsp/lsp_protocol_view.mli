(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** LSP JSON view helpers used by request handlers. *)

module Lsp_types = Lsp.Types

val lsp_location_json :
  uri:string -> line:int -> c1:int -> c2:int -> Yojson.Safe.t

val hover_json :
  ident:string -> kind:string -> occurrences:int -> Yojson.Safe.t

val completion_item_json : string -> Yojson.Safe.t
val completion_list_json : Yojson.Safe.t list -> Yojson.Safe.t

val full_document_text_edit_json :
  line_count:int -> new_text:string -> Yojson.Safe.t

val protocol_request_id : Jsonrpc.Id.t -> Lsp_protocol.rpc_request_id

val send_publish_diagnostics :
  out_channel ->
  uri:string ->
  diagnostics:Yojson.Safe.t list ->
  unit

val parse_diagnostics_for_text :
  uri:string -> text:string -> Yojson.Safe.t list

val symbol_info :
  uri:string -> name:string -> line:int -> character:int -> Yojson.Safe.t
