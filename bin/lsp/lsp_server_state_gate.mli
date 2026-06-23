(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Pure state gate for regular initialized-method dispatch. *)

type rejection = {
  code : int;
  message : string;
}

type t =
  | Allow
  | Reject of rejection

val check_regular_dispatch : Lsp_server_state.t -> t
