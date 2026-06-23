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

let dot_png_from_text oc ~id ~params =
  match Lsp_graph_decode.dot_text params with
  | Some dot ->
      let out =
        Lsp_backend_graph.dot_png_from_text { Lsp_protocol.dot_text = dot }
      in
      send_result oc ~id_json:id
        ~result_json:(match out with None -> `Null | Some s -> `String s)
  | None ->
      send_error oc ~id_json:(Some id) ~code:(-32602) ~message:"Missing dotText"
