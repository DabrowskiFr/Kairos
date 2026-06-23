(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Decode non-streaming Kairos pipeline pass requests, including legacy JSON. *)

val instrumentation_pass :
  Yojson.Safe.t ->
  Lsp_protocol.instrumentation_pass_request option

val why_pass :
  Yojson.Safe.t ->
  Lsp_protocol.why_pass_request option

val obligations_pass :
  Yojson.Safe.t ->
  Lsp_protocol.obligations_pass_request option
