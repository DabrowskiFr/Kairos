(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type ready = {
  req_key : string;
  decoded : Lsp_run_config.decoded;
}

type t =
  | Canceled
  | Invalid_input
  | Ready of ready

let is_canceled ctx ready =
  Lsp_run_context.is_canceled_key ctx ready.req_key

let check ctx ~id ~params =
  let req_key = Lsp_transport.id_key id in
  if Lsp_run_context.is_canceled_key ctx req_key then Canceled
  else
    match Lsp_run_config.decode params with
    | Some decoded when Sys.file_exists decoded.input_file ->
        Ready { req_key; decoded }
    | _ -> Invalid_input
