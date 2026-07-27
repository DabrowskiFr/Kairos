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

let method_not_found oc id_json =
  Option.iter
    (fun id ->
      send_error oc ~id_json:(Some id) ~code:(-32601)
        ~message:"Method not found")
    id_json

let invalid_request oc id_json =
  Option.iter
    (fun id ->
      send_error oc ~id_json:(Some id) ~code:(-32600)
        ~message:"Invalid request")
    id_json

type family_dispatch =
  out_channel ->
  Lsp_server_state.t ->
  method_name:string ->
  id_json:Jsonrpc.Id.t option ->
  params:Yojson.Safe.t ->
  bool

let families : (string * family_dispatch) list =
  [
    ("standard", Lsp_standard_method_route.try_dispatch);
    ("kairos", Lsp_kairos_method_route.try_dispatch);
    ("run", Lsp_run_method_route.try_dispatch);
  ]

let dispatch_known_method oc state ~method_name ~id_json ~params =
  List.exists
    (fun (_name, dispatch_family) ->
      dispatch_family oc state ~method_name ~id_json ~params)
    families

let dispatch oc (state : Lsp_server_state.t) ~method_name ~id_json ~params =
  match method_name with
  | None -> invalid_request oc id_json
  | Some method_name ->
      if dispatch_known_method oc state ~method_name ~id_json ~params then ()
      else method_not_found oc id_json
