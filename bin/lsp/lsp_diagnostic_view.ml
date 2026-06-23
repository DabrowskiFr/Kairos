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

module Lsp_types = Lsp.Types

let diagnostic_to_json (d : Lsp_diagnostics.diagnostic) : Yojson.Safe.t =
  let severity =
    match d.severity with
    | 1 -> Some Lsp_types.DiagnosticSeverity.Error
    | 2 -> Some Lsp_types.DiagnosticSeverity.Warning
    | 3 -> Some Lsp_types.DiagnosticSeverity.Information
    | 4 -> Some Lsp_types.DiagnosticSeverity.Hint
    | _ -> None
  in
  let range =
    let start = Lsp_location_view.lsp_position ~line:d.line ~character:d.col in
    let end_ =
      Lsp_location_view.lsp_position ~line:d.line ~character:(d.col + 1)
    in
    Lsp_types.Range.create ~start ~end_
  in
  Lsp_types.Diagnostic.create ~message:(`String d.message) ~range ?severity
    ~source:d.source ()
  |> Lsp_types.Diagnostic.yojson_of_t

let send_publish_diagnostics
    (oc : out_channel)
    ~(uri : string)
    ~(diagnostics : Yojson.Safe.t list) : unit =
  let diagnostics =
    List.filter_map
      (fun json ->
        try Some (Lsp_types.Diagnostic.t_of_yojson json) with _ -> None)
      diagnostics
  in
  let params =
    Lsp_types.PublishDiagnosticsParams.create
      ~uri:(Lsp_types.DocumentUri.of_string uri)
      ~diagnostics ()
  in
  send_notification oc ~method_name:"textDocument/publishDiagnostics"
    ~params_json:(Lsp_types.PublishDiagnosticsParams.yojson_of_t params)

let parse_diagnostics_for_text ~(uri : string) ~(text : string) :
    Yojson.Safe.t list =
  Lsp_diagnostics.diagnostics_for_text ~uri ~text
  |> List.map diagnostic_to_json
