(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

open Lsp_transport

let reject_if_request oc id_json ~code ~message =
  if is_request id_json then send_error oc ~id_json ~code ~message

let dispatch oc (state : Lsp_server_state.t) (call : Lsp_call.t) =
  match Lsp_server_state_gate.check_regular_dispatch state with
  | Reject { code; message } -> reject_if_request oc call.id_json ~code ~message
  | Allow ->
    Lsp_method_dispatch.dispatch oc state ~method_name:call.method_name
      ~id_json:call.id_json ~params:call.params
