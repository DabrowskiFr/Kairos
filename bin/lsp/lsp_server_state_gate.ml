(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type rejection = {
  code : int;
  message : string;
}

type t =
  | Allow
  | Reject of rejection

let check_regular_dispatch (state : Lsp_server_state.t) =
  if not !(state.initialized) then
    Reject { code = -32002; message = "Server not initialized" }
  else if !(state.shutdown_requested) then
    Reject { code = -32600; message = "Invalid request: server is shut down" }
  else Allow
