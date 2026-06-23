(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Work-done progress transport messages. *)

val send_begin :
  out_channel -> token:string -> title:string -> message:string -> unit

val send_report : out_channel -> token:string -> message:string -> unit
val send_end : out_channel -> token:string -> message:string -> unit
