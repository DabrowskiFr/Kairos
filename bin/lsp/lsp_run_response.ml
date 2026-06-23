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

let send_canceled out_channel ~id =
  send_error out_channel ~id_json:(Some id) ~code:(-32800)
    ~message:"Request cancelled"

let send_invalid_input out_channel ~id =
  send_error out_channel ~id_json:(Some id) ~code:(-32602)
    ~message:"Missing valid inputFile"

let send_backend_error out_channel ~id message =
  send_error out_channel ~id_json:(Some id) ~code:(-32001) ~message

let send_outputs out_channel ~id out =
  send_result out_channel ~id_json:id
    ~result_json:(Lsp_protocol.yojson_of_outputs out)
