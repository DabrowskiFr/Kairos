(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Dispatch initialized standard LSP methods. *)

val dispatch :
  out_channel ->
  Lsp_server_state.t ->
  method_name:string ->
  id_json:Jsonrpc.Id.t option ->
  params:Yojson.Safe.t ->
  bool
