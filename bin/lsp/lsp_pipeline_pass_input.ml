(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let valid_file path = Sys.file_exists path

let reject_missing_input_file oc ~id ~message =
  Lsp_transport.send_error oc ~id_json:(Some id) ~code:(-32602) ~message
