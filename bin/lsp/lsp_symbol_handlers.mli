(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Handlers for LSP symbol navigation and symbol listing requests. *)

val hover :
  out_channel ->
  docs:Lsp_document_store.t ->
  id:Jsonrpc.Id.t ->
  params:Yojson.Safe.t ->
  unit

val definition :
  out_channel ->
  docs:Lsp_document_store.t ->
  id:Jsonrpc.Id.t ->
  params:Yojson.Safe.t ->
  unit

val references :
  out_channel ->
  docs:Lsp_document_store.t ->
  id:Jsonrpc.Id.t ->
  params:Yojson.Safe.t ->
  unit

val document_symbol :
  out_channel ->
  docs:Lsp_document_store.t ->
  id:Jsonrpc.Id.t ->
  params:Yojson.Safe.t ->
  unit

val workspace_symbol : out_channel -> id:Jsonrpc.Id.t -> unit
