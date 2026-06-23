(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** State transitions for lifecycle requests. *)

type initialize_result =
  | Already_initialized
  | Initialized

type shutdown_result =
  | Not_initialized
  | Shutdown_requested

val initialize :
  Lsp_server_state.t -> params:Yojson.Safe.t -> initialize_result

val shutdown : Lsp_server_state.t -> shutdown_result
val exit_code : Lsp_server_state.t -> int
