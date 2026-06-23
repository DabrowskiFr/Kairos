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

let completion_item_json (label : string) : Yojson.Safe.t =
  Lsp_types.CompletionItem.create ~label
    ~kind:Lsp_types.CompletionItemKind.Function ~insertText:label ()
  |> Lsp_types.CompletionItem.yojson_of_t

let completion_list_json (items : Yojson.Safe.t list) : Yojson.Safe.t =
  let items =
    List.filter_map
      (fun json ->
        try Some (Lsp_types.CompletionItem.t_of_yojson json) with _ -> None)
      items
  in
  Lsp_types.CompletionList.create ~isIncomplete:false ~items ()
  |> Lsp_types.CompletionList.yojson_of_t
