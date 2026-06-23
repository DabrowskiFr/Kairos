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
  on_outputs_ready : Lsp_protocol.outputs -> unit;
  on_goals_ready : string list * int list -> unit;
  on_goal_done :
    int ->
    string ->
    string ->
    float ->
    string option ->
    string option ->
    unit;
}

let create ~out_channel ~id ~progress ~prove =
  let completed_goals = ref 0 in
  let total_goals = ref 0 in
  let on_outputs_ready out =
    Lsp_run_progress.report progress
      ~message:
        (if prove then "Proof results ready; publishing goals ..."
         else "Artifacts ready");
    let payload : Lsp_protocol.outputs_ready_notification =
      { request_id = Lsp_request_id_view.protocol_request_id id; payload = out }
    in
    send_notification out_channel ~method_name:"kairos/outputsReady"
      ~params_json:
        (Lsp_protocol.yojson_of_outputs_ready_notification payload)
  in
  let on_goals_ready (names, vc_ids) =
    total_goals := max (List.length names) (List.length vc_ids);
    Lsp_run_progress.report progress
      ~message:
        (if !total_goals > 0 then
           Printf.sprintf "Publishing %d proof goals ..." !total_goals
         else "Publishing proof goals ...");
    let payload : Lsp_protocol.goals_ready_notification =
      {
        request_id = Lsp_request_id_view.protocol_request_id id;
        payload = { names; vc_ids };
      }
    in
    send_notification out_channel ~method_name:"kairos/goalsReady"
      ~params_json:
        (Lsp_protocol.yojson_of_goals_ready_notification payload)
  in
  let on_goal_done idx goal status time_s dump_path vcid =
    incr completed_goals;
    Lsp_run_progress.report progress
      ~message:
        (if !total_goals > 0 then
           Printf.sprintf "Goal %d/%d: %s" !completed_goals !total_goals
             status
         else Printf.sprintf "Goal %d: %s" (idx + 1) status);
    let payload : Lsp_protocol.goal_done_notification =
      {
        request_id = Lsp_request_id_view.protocol_request_id id;
        payload = { idx; goal; status; time_s; dump_path; vcid };
      }
    in
    send_notification out_channel ~method_name:"kairos/goalDone"
      ~params_json:(Lsp_protocol.yojson_of_goal_done_notification payload)
  in
  { on_outputs_ready; on_goals_ready; on_goal_done }
