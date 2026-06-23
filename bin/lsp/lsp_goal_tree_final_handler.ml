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

let goals_tree_final oc ~id ~params =
  let req = Lsp_goal_tree_decode.final params in
  let nodes = Lsp_goal_tree.goals_tree_final ~goals:req.goals ~vc_text:req.vc_text in
  send_result oc ~id_json:id ~result_json:(Lsp_goal_tree_view.json_of_nodes nodes)
