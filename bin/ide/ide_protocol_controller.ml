type t = { add_history : string -> unit }

let create ~add_history =
  let t = { add_history } in
  Ide_lsp_bridge.set_notification_handler (function
    | Ide_lsp_types.Progress { phase; message; _ } ->
        let suffix = match message with None -> "" | Some m -> " (" ^ m ^ ")" in
        t.add_history ("Protocol: " ^ phase ^ suffix)
    | Ide_lsp_types.Publish_diagnostic { stage; message } ->
        t.add_history ("Diagnostic[" ^ stage ^ "]: " ^ message)
    | Ide_lsp_types.Goals_ready _ | Ide_lsp_types.Goal_done _ | Ide_lsp_types.Outputs_ready _ ->
        ());
  t

let cancel_active _t = Ide_lsp_bridge.cancel_active ()
let did_open _t ~uri ~text = ignore (Ide_lsp_bridge.did_open ~uri ~text)
let did_change _t ~uri ~version ~text = ignore (Ide_lsp_bridge.did_change ~uri ~version ~text)
let did_save _t ~uri = ignore (Ide_lsp_bridge.did_save ~uri)
let did_close _t ~uri = ignore (Ide_lsp_bridge.did_close ~uri)

let hover _t ~uri ~line ~character =
  match Ide_lsp_bridge.hover ~uri ~line ~character with Ok x -> x | Error _ -> None

let definition _t ~uri ~line ~character =
  match Ide_lsp_bridge.definition ~uri ~line ~character with Ok x -> Some x | Error _ -> None

let references _t ~uri ~line ~character =
  match Ide_lsp_bridge.references ~uri ~line ~character with Ok x -> x | Error _ -> []

let completion _t ~uri ~line ~character =
  match Ide_lsp_bridge.completion ~uri ~line ~character with Ok x -> x | Error _ -> []

let formatting _t ~uri =
  match Ide_lsp_bridge.formatting ~uri with Ok x -> x | Error _ -> None

let outline _t ~uri ~abstract_text =
  match Ide_lsp_bridge.outline ~uri ~abstract_text with Ok x -> Some x | Error _ -> None

let goals_tree_final _t ~goals ~vc_sources ~vc_text =
  match Ide_lsp_bridge.goals_tree_final ~goals ~vc_sources ~vc_text with
  | Ok x -> x
  | Error _ -> []

let goals_tree_pending _t ~goal_names ~vc_ids ~vc_sources =
  match Ide_lsp_bridge.goals_tree_pending ~goal_names ~vc_ids ~vc_sources with
  | Ok x -> x
  | Error _ -> []
