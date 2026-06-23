(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Decode document synchronization notifications. *)

type text_update = {
  uri : string;
  text : string;
}

val did_open : Yojson.Safe.t -> text_update option
val did_change : Yojson.Safe.t -> text_update option
val document_uri : Yojson.Safe.t -> string option
