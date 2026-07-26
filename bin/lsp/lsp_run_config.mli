(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Decode [kairos/run] request parameters into backend configuration. *)

type decoded = {
  cfg : Lsp_protocol.config;
  engine : Engine_service.engine;
  input_file : string;
}

val decode : Yojson.Safe.t -> decoded option
val lsp_config : decoded -> Lsp_protocol.config
