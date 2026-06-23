(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type initialize_result =
  | Already_initialized
  | Initialized

type shutdown_result =
  | Not_initialized
  | Shutdown_requested

let initialize (state : Lsp_server_state.t) ~params =
  if !(state.initialized) then Already_initialized
  else (
    state.initialized := true;
    state.supports_work_done_progress :=
      Lsp_request_decode.client_supports_work_done_progress params;
    Initialized)

let shutdown (state : Lsp_server_state.t) =
  if not !(state.initialized) then Not_initialized
  else (
    state.shutdown_requested := true;
    Shutdown_requested)

let exit_code (state : Lsp_server_state.t) =
  if !(state.shutdown_requested) then 0 else 1
