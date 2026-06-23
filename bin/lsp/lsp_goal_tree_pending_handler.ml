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

let goals_tree_pending oc ~id ~params =
  let req = Lsp_goal_tree_decode.pending params in
  let nodes =
    Lsp_goal_tree.goals_tree_pending ~goal_names:req.goal_names
      ~vc_ids:req.vc_ids
  in
  send_result oc ~id_json:id ~result_json:(Lsp_goal_tree_view.json_of_nodes nodes)
