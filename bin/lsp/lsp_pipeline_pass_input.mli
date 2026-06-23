(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Common input-file validation/reporting for non-streaming pipeline passes. *)

val valid_file : string -> bool

val reject_missing_input_file :
  out_channel ->
  id:Jsonrpc.Id.t ->
  message:string ->
  unit
