(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module Sync_io = struct
  type 'a t = 'a

  let return x = x
  let raise exn = Stdlib.raise exn

  module O = struct
    let ( let+ ) x f = f x
    let ( let* ) x f = f x
  end
end

module Channels = struct
  type input = in_channel
  type output = out_channel

  let read_line ic =
    try Some (input_line ic) with End_of_file -> None

  let read_exactly ic len =
    try Some (really_input_string ic len) with End_of_file -> None

  let write oc parts =
    List.iter (output_string oc) parts;
    flush oc
end

module Transport = Lsp.Io.Make (Sync_io) (Channels)
