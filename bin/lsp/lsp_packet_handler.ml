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

let unsupported_batch_call oc =
  send_error_raw oc ~id_json:None ~code:(-32600)
    ~message:"Batch requests are not supported"

let handle_decoded oc state = function
  | Lsp_packet_decode.Ignore -> ()
  | Unsupported_batch_call -> unsupported_batch_call oc
  | Call call -> Lsp_call_dispatch.dispatch oc state call

let handle oc state packet =
  Lsp_packet_decode.of_packet packet |> handle_decoded oc state
