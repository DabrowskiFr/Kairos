(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Notifications emitted while a [kairos/run] request is executing. *)

type t = {
  on_outputs_ready : Lsp_protocol.outputs -> unit;
  on_goals_ready : string list * int list -> unit;
  on_goal_done :
    int ->
    string ->
    string ->
    float ->
    string option ->
    string option ->
    unit;
}

val create :
  out_channel:out_channel ->
  id:Jsonrpc.Id.t ->
  progress:Lsp_run_progress.t ->
  prove:bool ->
  t
