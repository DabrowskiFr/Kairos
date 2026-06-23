(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Common route kernel for LSP method families. *)

type 'ctx t

val any : string -> ('ctx -> unit) -> 'ctx t
val notification : string -> ('ctx -> unit) -> 'ctx t
val request : string -> ('ctx -> id:Jsonrpc.Id.t -> unit) -> 'ctx t
val find : 'ctx t list -> string -> 'ctx t option
val dispatch : 'ctx t -> 'ctx -> id_json:Jsonrpc.Id.t option -> unit
