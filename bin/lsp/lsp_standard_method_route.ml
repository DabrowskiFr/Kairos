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

let notification = Lsp_method_route.notification
let request = Lsp_method_route.request

let routes : t list =
  [
    notification "textDocument/didOpen" (fun ctx ->
        Lsp_document_sync_handlers.did_open ctx.out_channel ~docs:ctx.state.docs
          ~params:ctx.params);
    notification "textDocument/didChange" (fun ctx ->
        Lsp_document_sync_handlers.did_change ctx.out_channel ~docs:ctx.state.docs
          ~params:ctx.params);
    notification "textDocument/didSave" (fun ctx ->
        Lsp_document_sync_handlers.did_save ctx.out_channel ~docs:ctx.state.docs
          ~params:ctx.params);
    notification "textDocument/didClose" (fun ctx ->
        Lsp_document_sync_handlers.did_close ctx.out_channel ~docs:ctx.state.docs
          ~params:ctx.params);
    request "textDocument/hover" (fun ctx ~id ->
        Lsp_hover_handler.hover ctx.out_channel ~docs:ctx.state.docs ~id
          ~params:ctx.params);
    request "textDocument/definition" (fun ctx ~id ->
        Lsp_definition_handler.definition ctx.out_channel ~docs:ctx.state.docs
          ~id ~params:ctx.params);
    request "textDocument/references" (fun ctx ~id ->
        Lsp_references_handler.references ctx.out_channel ~docs:ctx.state.docs
          ~id ~params:ctx.params);
    request "textDocument/completion" (fun ctx ~id ->
        Lsp_completion_handler.completion ctx.out_channel ~docs:ctx.state.docs
          ~id ~params:ctx.params);
    request "textDocument/documentSymbol" (fun ctx ~id ->
        Lsp_document_symbol_handler.document_symbol ctx.out_channel
          ~docs:ctx.state.docs ~id ~params:ctx.params);
    request "workspace/symbol" (fun ctx ~id ->
        Lsp_workspace_symbol_handler.workspace_symbol ctx.out_channel ~id);
    request "textDocument/formatting" (fun ctx ~id ->
        Lsp_formatting_handler.formatting ctx.out_channel ~docs:ctx.state.docs
          ~id ~params:ctx.params);
  ]

let try_dispatch out_channel (state : Lsp_server_state.t) ~method_name ~id_json
    ~params =
  match Lsp_method_route.find routes method_name with
  | None -> false
  | Some route ->
      let ctx = { out_channel; state; params } in
      Lsp_method_route.dispatch route ctx ~id_json;
      true
