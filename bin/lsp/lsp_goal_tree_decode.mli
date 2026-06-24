(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Decode proof-goal tree requests, including compatibility JSON payloads. *)

type final_request = {
  goals : Pipeline_types.goal_info list;
  vc_text : string;
}

type pending_request = {
  goal_names : string list;
  vc_ids : int list;
}

val final : Yojson.Safe.t -> final_request
val pending : Yojson.Safe.t -> pending_request
