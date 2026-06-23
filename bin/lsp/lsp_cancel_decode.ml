(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let id_of_params = function
  | `Assoc fields -> (
      match List.assoc_opt "id" fields with
      | Some id_json -> (
          try Some (Jsonrpc.Id.t_of_yojson id_json) with _ -> None)
      | None -> None)
  | _ -> None
