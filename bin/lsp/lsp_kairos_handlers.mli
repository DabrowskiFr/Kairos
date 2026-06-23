(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Compatibility facade for non-streaming [kairos/*] LSP extension methods. *)

type document_store = Lsp_document_store.t

val outline :
  out_channel ->
  docs:document_store ->
  id:Jsonrpc.Id.t ->
  params:Yojson.Safe.t ->
  unit

val goals_tree_final : out_channel -> id:Jsonrpc.Id.t -> params:Yojson.Safe.t -> unit

val goals_tree_pending : out_channel -> id:Jsonrpc.Id.t -> params:Yojson.Safe.t -> unit

val instrumentation_pass :
  out_channel -> id:Jsonrpc.Id.t -> params:Yojson.Safe.t -> unit

val why_pass : out_channel -> id:Jsonrpc.Id.t -> params:Yojson.Safe.t -> unit

val obligations_pass : out_channel -> id:Jsonrpc.Id.t -> params:Yojson.Safe.t -> unit

val dot_png_from_text : out_channel -> id:Jsonrpc.Id.t -> params:Yojson.Safe.t -> unit
