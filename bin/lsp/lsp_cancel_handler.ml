(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let cancel_request (state : Lsp_server_state.t) ~params =
  Option.iter
    (Lsp_cancel_state.mark_canceled state)
    (Lsp_cancel_decode.id_of_params params)
