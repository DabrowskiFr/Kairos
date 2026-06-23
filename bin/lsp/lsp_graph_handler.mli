(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Handler for Graphviz DOT-to-PNG requests. *)

val dot_png_from_text :
  out_channel ->
  id:Jsonrpc.Id.t ->
  params:Yojson.Safe.t ->
  unit
