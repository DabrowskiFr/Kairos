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

type t = {
  out_channel : out_channel;
  token : string;
  enabled : bool;
}

let start (ctx : Lsp_run_context.t) =
  let token = "kairos-run-" ^ string_of_int !(ctx.next_server_req_id) in
  let enabled = !(ctx.supports_work_done_progress) in
  if enabled then (
    send_request ctx.out_channel ~id_json:(`Int !(ctx.next_server_req_id))
      ~method_name:"window/workDoneProgress/create"
      ~params_json:(`Assoc [ ("token", `String token) ]);
    incr ctx.next_server_req_id;
    send_work_done_begin ctx.out_channel ~token ~title:"Kairos run"
      ~message:"Starting");
  { out_channel = ctx.out_channel; token; enabled }

let report t ~message =
  if t.enabled then send_work_done_report t.out_channel ~token:t.token ~message

let finish t ~message =
  if t.enabled then send_work_done_end t.out_channel ~token:t.token ~message
