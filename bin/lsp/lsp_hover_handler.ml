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

let hover oc ~(docs : Lsp_document_store.t) ~id ~params =
  let result =
    match Lsp_symbol_context.resolve docs params with
    | Some ctx -> (
        match Lsp_symbols.symbol_kind ctx.symbols ctx.ident with
        | None -> `Null
        | Some kind ->
            let occurrences =
              List.length
                (Lsp_symbols.identifier_occurrences ctx.text ctx.ident)
            in
            Lsp_hover_view.hover_json ~ident:ctx.ident ~kind ~occurrences)
    | None -> `Null
  in
  send_result oc ~id_json:id ~result_json:result
