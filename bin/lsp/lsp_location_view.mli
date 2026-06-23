(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** LSP position, range, and location rendering helpers. *)

module Lsp_types = Lsp.Types

val lsp_position : line:int -> character:int -> Lsp_types.Position.t
val lsp_range : line:int -> c1:int -> c2:int -> Lsp_types.Range.t

val lsp_location_json :
  uri:string ->
  line:int ->
  c1:int ->
  c2:int ->
  Yojson.Safe.t
