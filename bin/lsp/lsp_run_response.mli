(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** JSON-RPC responses for [kairos/run]. *)

val send_canceled : out_channel -> id:Jsonrpc.Id.t -> unit
val send_invalid_input : out_channel -> id:Jsonrpc.Id.t -> unit
val send_backend_error : out_channel -> id:Jsonrpc.Id.t -> string -> unit
val send_outputs : out_channel -> id:Jsonrpc.Id.t -> Lsp_protocol.outputs -> unit
