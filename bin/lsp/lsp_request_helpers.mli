(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Shared decoding helpers for LSP request handlers. *)

val decode_or_none : (Yojson.Safe.t -> ('a, string) result) -> Yojson.Safe.t -> 'a option

val get_engine : Yojson.Safe.t -> Engine_service.engine
