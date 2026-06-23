(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let is_request id_json = Option.is_some id_json
let key (id : Jsonrpc.Id.t) = Jsonrpc.Id.yojson_of_t id |> Yojson.Safe.to_string
