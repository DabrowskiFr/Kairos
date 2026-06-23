(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let dispatch out_channel (state : Lsp_server_state.t) ~method_name ~id_json
    ~params =
  match Lsp_run_method_route.find method_name with
  | None -> false
  | Some route ->
      let ctx : Lsp_run_method_route.context =
        {
          run_context = Lsp_run_context.of_server_state out_channel state;
          params;
        }
      in
      Lsp_run_method_route.dispatch route ctx ~id_json;
      true
