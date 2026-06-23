(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let decode_or_none decode json =
  match decode json with
  | Ok value -> Some value
  | Error _ -> None

let get_engine (params : Yojson.Safe.t) : Engine_service.engine =
  match Lsp_request_decode.get_param_string params "engine" with
  | Some s ->
      Option.value (Engine_service.engine_of_string s)
        ~default:Engine_service.Default
  | None -> Engine_service.Default
