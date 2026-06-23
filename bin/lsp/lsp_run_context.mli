(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Shared mutable state needed by the streaming [kairos/run] handler. *)

type t = {
  out_channel : out_channel;
  canceled : (string, unit) Hashtbl.t;
  next_server_req_id : int ref;
  supports_work_done_progress : bool ref;
}

val of_server_state : out_channel -> Lsp_server_state.t -> t
val is_canceled_key : t -> string -> bool
