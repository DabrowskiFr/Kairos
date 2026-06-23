(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type t = Lsp_run_context.t = {
  out_channel : out_channel;
  canceled : (string, unit) Hashtbl.t;
  next_server_req_id : int ref;
  supports_work_done_progress : bool ref;
}

let handle = Lsp_run_execution_handler.handle
