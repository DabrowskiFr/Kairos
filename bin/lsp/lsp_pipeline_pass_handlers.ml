(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let instrumentation_pass = Lsp_instrumentation_pass_handler.instrumentation_pass
let why_pass = Lsp_why_pass_handler.why_pass
let obligations_pass = Lsp_obligations_pass_handler.obligations_pass
