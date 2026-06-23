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

let send_error_if_request oc id_json ~code ~message =
  if is_request id_json then send_error oc ~id_json ~code ~message

let send_result_if_request oc id_json ~result_json =
  Option.iter (fun id -> send_result oc ~id_json:id ~result_json) id_json

let initialize oc (state : Lsp_server_state.t) ~id_json ~params =
  match Lsp_lifecycle_state.initialize state ~params with
  | Already_initialized ->
      send_error_if_request oc id_json ~code:(-32600)
        ~message:"Server already initialized"
  | Initialized ->
      send_result_if_request oc id_json
        ~result_json:(Lsp_initialize_result_view.yojson ())

let initialized (_state : Lsp_server_state.t) = ()

let shutdown oc (state : Lsp_server_state.t) ~id_json =
  match Lsp_lifecycle_state.shutdown state with
  | Not_initialized ->
      send_error_if_request oc id_json ~code:(-32002)
        ~message:"Server not initialized"
  | Shutdown_requested -> send_result_if_request oc id_json ~result_json:`Null

let exit_server state = exit (Lsp_lifecycle_state.exit_code state)
