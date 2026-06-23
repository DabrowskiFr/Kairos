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

let symbol_info ~(uri : string) ~(name : string) ~(line : int)
    ~(character : int) : Yojson.Safe.t =
  let range =
    let start = Lsp_location_view.lsp_position ~line ~character in
    let end_ = Lsp_location_view.lsp_position ~line ~character:(character + 1) in
    Lsp_types.Range.create ~start ~end_
  in
  let location =
    Lsp_types.Location.create ~uri:(Lsp_types.DocumentUri.of_string uri) ~range
  in
  Lsp_types.SymbolInformation.create ~name ~kind:Lsp_types.SymbolKind.Function
    ~location ()
  |> Lsp_types.SymbolInformation.yojson_of_t
