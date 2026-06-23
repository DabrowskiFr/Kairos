(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Mutable state shared by the Kairos LSP server loop and dispatchers. *)

type t = {
  docs : Lsp_document_store.t;
  canceled : (string, unit) Hashtbl.t;
  next_server_req_id : int ref;
  initialized : bool ref;
  shutdown_requested : bool ref;
  supports_work_done_progress : bool ref;
  running : bool ref;
}

val create : unit -> t
