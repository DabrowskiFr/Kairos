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

let lsp_position ~line ~character =
  Lsp_types.Position.create ~line ~character

let lsp_range ~line ~c1 ~c2 =
  let start = lsp_position ~line ~character:c1 in
  let end_ = lsp_position ~line ~character:c2 in
  Lsp_types.Range.create ~start ~end_

let lsp_location_json ~uri ~line ~c1 ~c2 : Yojson.Safe.t =
  Lsp_types.Location.create
    ~uri:(Lsp_types.DocumentUri.of_string uri)
    ~range:(lsp_range ~line ~c1 ~c2)
  |> Lsp_types.Location.yojson_of_t
