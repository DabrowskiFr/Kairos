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
  params : Yojson.Safe.t;
}

type t = context Lsp_method_route.t

let request = Lsp_method_route.request

let routes : t list =
  [
    request "kairos/outline" (fun ctx ~id ->
        Lsp_outline_request_handler.outline ctx.out_channel ~docs:ctx.state.docs
          ~id ~params:ctx.params);
    request "kairos/goalsTreeFinal" (fun ctx ~id ->
        Lsp_goal_tree_final_handler.goals_tree_final ctx.out_channel ~id
          ~params:ctx.params);
    request "kairos/goalsTreePending" (fun ctx ~id ->
        Lsp_goal_tree_pending_handler.goals_tree_pending ctx.out_channel ~id
          ~params:ctx.params);
    request "kairos/instrumentationPass" (fun ctx ~id ->
        Lsp_instrumentation_pass_handler.instrumentation_pass ctx.out_channel
          ~id ~params:ctx.params);
    request "kairos/whyPass" (fun ctx ~id ->
        Lsp_why_pass_handler.why_pass ctx.out_channel ~id ~params:ctx.params);
    request "kairos/obligationsPass" (fun ctx ~id ->
        Lsp_obligations_pass_handler.obligations_pass ctx.out_channel ~id
          ~params:ctx.params);
    request "kairos/dotPngFromText" (fun ctx ~id ->
        Lsp_graph_handler.dot_png_from_text ctx.out_channel ~id
          ~params:ctx.params);
  ]

let try_dispatch out_channel (state : Lsp_server_state.t) ~method_name ~id_json
    ~params =
  match Lsp_method_route.find routes method_name with
  | None -> false
  | Some route ->
      let ctx = { out_channel; state; params } in
      Lsp_method_route.dispatch route ctx ~id_json;
      true
