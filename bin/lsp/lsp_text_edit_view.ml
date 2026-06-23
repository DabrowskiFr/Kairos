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

let full_document_text_edit_json ~line_count ~new_text : Yojson.Safe.t =
  Lsp_types.TextEdit.create ~newText:new_text
    ~range:(Lsp_location_view.lsp_range ~line:0 ~c1:0 ~c2:0)
  |> fun edit ->
  let range =
    let start = Lsp_location_view.lsp_position ~line:0 ~character:0 in
    let end_ =
      Lsp_location_view.lsp_position ~line:line_count ~character:0
    in
    Lsp_types.Range.create ~start ~end_
  in
  { edit with range } |> Lsp_types.TextEdit.yojson_of_t
