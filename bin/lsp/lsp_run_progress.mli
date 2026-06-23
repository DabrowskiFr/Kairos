(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Work-done progress reporting for the streaming [kairos/run] request. *)

type t

val start : Lsp_run_context.t -> t
val report : t -> message:string -> unit
val finish : t -> message:string -> unit
