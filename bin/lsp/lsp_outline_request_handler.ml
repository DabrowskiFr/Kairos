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

let outline oc ~(docs : Lsp_document_store.t) ~id ~params =
  let req = Lsp_outline_decode.of_params params in
  let texts = Lsp_outline_texts.resolve ~docs req in
  send_result oc ~id_json:id ~result_json:(Lsp_outline_view.yojson_of_texts texts)
