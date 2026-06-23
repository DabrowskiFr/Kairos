(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Normalize raw JSON-RPC packets into router-level events. *)

type t =
  | Ignore
  | Unsupported_batch_call
  | Call of Lsp_call.t

val of_packet : Jsonrpc.Packet.t -> t
