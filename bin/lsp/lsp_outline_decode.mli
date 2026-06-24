(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Decode outline requests, including compatibility JSON payloads. *)

type t = {
  uri : string option;
  source_text : string option;
  abstract_text : string option;
}

val of_params : Yojson.Safe.t -> t
