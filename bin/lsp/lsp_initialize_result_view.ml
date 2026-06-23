(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module Lsp_types = Lsp.Types

let yojson () =
  let capabilities =
    Lsp_types.ServerCapabilities.create
      ~textDocumentSync:
        (`TextDocumentSyncOptions
          (Lsp_types.TextDocumentSyncOptions.create ~openClose:true
             ~change:Lsp_types.TextDocumentSyncKind.Full
             ~save:
               (`SaveOptions
                 (Lsp_types.SaveOptions.create ~includeText:false ()))
             ()))
      ~hoverProvider:(`Bool true)
      ~definitionProvider:(`Bool true)
      ~referencesProvider:(`Bool true)
      ~documentSymbolProvider:(`Bool true)
      ~completionProvider:
        (Lsp_types.CompletionOptions.create ~triggerCharacters:[] ())
      ~workspaceSymbolProvider:(`Bool true)
      ~documentFormattingProvider:(`Bool true) ()
  in
  Lsp_types.InitializeResult.create ~capabilities
    ~serverInfo:
      (Lsp_types.InitializeResult.create_serverInfo ~name:"kairos-lsp"
         ~version:"1.0" ())
    ()
  |> Lsp_types.InitializeResult.yojson_of_t
