(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** LSP diagnostic rendering and publishing helpers. *)

val send_publish_diagnostics :
  out_channel ->
  uri:string ->
  diagnostics:Yojson.Safe.t list ->
  unit

val parse_diagnostics_for_text :
  uri:string ->
  text:string ->
  Yojson.Safe.t list
