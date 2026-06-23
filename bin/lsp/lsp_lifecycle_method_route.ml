(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type context = {
  out_channel : out_channel;
  state : Lsp_server_state.t;
  call : Lsp_call.t;
}

type t = context Lsp_method_route.t

let any = Lsp_method_route.any

let routes : t list =
  [
    any "initialize" (fun ctx ->
        Lsp_lifecycle_handlers.initialize ctx.out_channel ctx.state
          ~id_json:ctx.call.id_json ~params:ctx.call.params);
    any "initialized" (fun ctx ->
        Lsp_lifecycle_handlers.initialized ctx.state);
    any "$/cancelRequest" (fun ctx ->
        Lsp_cancel_handler.cancel_request ctx.state ~params:ctx.call.params);
    any "shutdown" (fun ctx ->
        Lsp_lifecycle_handlers.shutdown ctx.out_channel ctx.state
          ~id_json:ctx.call.id_json);
    any "exit" (fun ctx -> Lsp_lifecycle_handlers.exit_server ctx.state);
  ]

let find method_name = Lsp_method_route.find routes method_name
let dispatch = Lsp_method_route.dispatch
