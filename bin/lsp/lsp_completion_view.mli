(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** LSP completion item/list rendering helpers. *)

val completion_item_json : string -> Yojson.Safe.t
val completion_list_json : Yojson.Safe.t list -> Yojson.Safe.t
