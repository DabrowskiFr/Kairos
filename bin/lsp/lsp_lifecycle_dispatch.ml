(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let dispatch out_channel (state : Lsp_server_state.t) (call : Lsp_call.t) =
  match Option.bind call.method_name Lsp_lifecycle_method_route.find with
  | None -> false
  | Some route ->
      let ctx : Lsp_lifecycle_method_route.context =
        { out_channel; state; call }
      in
      Lsp_lifecycle_method_route.dispatch route ctx ~id_json:call.id_json;
      true
