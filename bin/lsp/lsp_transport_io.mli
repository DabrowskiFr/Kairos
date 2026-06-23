(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Synchronous IO backend for the LSP library transport. *)

module Sync_io : sig
  type 'a t = 'a

  val return : 'a -> 'a
  val raise : exn -> 'a

  module O : sig
    val ( let+ ) : 'a -> ('a -> 'b) -> 'b
    val ( let* ) : 'a -> ('a -> 'b) -> 'b
  end
end

module Channels : sig
  type input = in_channel
  type output = out_channel

  val read_line : input -> string option
  val read_exactly : input -> int -> string option
  val write : output -> string list -> unit
end

module Transport : module type of Lsp.Io.Make (Sync_io) (Channels)
