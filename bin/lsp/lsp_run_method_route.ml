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
  run_context : Lsp_run_context.t;
  params : Yojson.Safe.t;
}

type t = context Lsp_method_route.t

let request = Lsp_method_route.request

let routes : t list =
  [
    request "kairos/run" (fun ctx ~id ->
        Lsp_run_execution_handler.handle ctx.run_context ~id
          ~params:ctx.params);
  ]

let find method_name = Lsp_method_route.find routes method_name
let dispatch = Lsp_method_route.dispatch
