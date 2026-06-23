(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let publish_text out_channel ~uri ~text =
  Lsp_diagnostic_view.send_publish_diagnostics out_channel ~uri
    ~diagnostics:(Lsp_diagnostic_view.parse_diagnostics_for_text ~uri ~text)

let publish_clear out_channel ~uri =
  Lsp_diagnostic_view.send_publish_diagnostics out_channel ~uri ~diagnostics:[]
