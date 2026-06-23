(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Decode and validate [kairos/run] requests before backend execution. *)

type ready = {
  req_key : string;
  decoded : Lsp_run_config.decoded;
}

type t =
  | Canceled
  | Invalid_input
  | Ready of ready

val check :
  Lsp_run_context.t -> id:Jsonrpc.Id.t -> params:Yojson.Safe.t -> t

val is_canceled : Lsp_run_context.t -> ready -> bool
