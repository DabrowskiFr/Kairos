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

let hover_json ~ident ~kind ~occurrences : Yojson.Safe.t =
  let value =
    Printf.sprintf "`%s` (%s)\n\nOccurrences in file: %d" ident kind
      occurrences
  in
  Lsp_types.Hover.create
    ~contents:
      (`MarkupContent
        (Lsp_types.MarkupContent.create ~kind:Lsp_types.MarkupKind.Markdown
           ~value))
    ()
  |> Lsp_types.Hover.yojson_of_t
