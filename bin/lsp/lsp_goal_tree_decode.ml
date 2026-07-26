(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

open Lsp_request_helpers

type final_request = {
  goals : Lsp_protocol.goal_info list;
  vc_text : string;
}

type pending_request = {
  goal_names : string list;
  vc_ids : int list;
}

let final params =
  match decode_or_none Lsp_protocol.goals_tree_final_request_of_yojson params with
  | Some req -> { goals = req.goals; vc_text = req.vc_text }
  | None ->
      let goals_json =
        Option.value (Lsp_request_decode.get_param_list params "goals")
          ~default:[]
      in
      let vc_text =
        Option.value (Lsp_request_decode.get_param_string params "vcText")
          ~default:""
      in
      let goals =
        List.filter_map
          (fun json ->
            match Lsp_protocol.goal_info_of_yojson json with
            | Ok value -> Some value
            | Error _ -> None)
          goals_json
      in
      { goals; vc_text }

let pending params =
  match decode_or_none Lsp_protocol.goals_tree_pending_request_of_yojson params with
  | Some req -> { goal_names = req.goal_names; vc_ids = req.vc_ids }
  | None ->
      let goal_names =
        Option.value (Lsp_request_decode.get_param_list params "goalNames")
          ~default:[]
        |> List.filter_map (function `String s -> Some s | _ -> None)
      in
      let vc_ids =
        Option.value (Lsp_request_decode.get_param_list params "vcIds")
          ~default:[]
        |> List.filter_map (function `Int i -> Some i | _ -> None)
      in
      { goal_names; vc_ids }
