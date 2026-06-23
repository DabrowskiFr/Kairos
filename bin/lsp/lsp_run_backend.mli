(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Backend execution for validated [kairos/run] requests. *)

val run :
  Lsp_run_preflight.ready ->
  Lsp_run_notifications.t ->
  should_cancel:(unit -> bool) ->
  (Lsp_protocol.outputs, string) result
