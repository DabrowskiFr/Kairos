(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Declarative routing table for initialized standard LSP methods. *)

type context = {
  out_channel : out_channel;
  state : Lsp_server_state.t;
  params : Yojson.Safe.t;
}

type t

val find : string -> t option
val dispatch : t -> context -> id_json:Jsonrpc.Id.t option -> unit
