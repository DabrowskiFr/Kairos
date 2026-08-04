(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

let rec write_all_bytes fd bytes offset length =
  if length > 0 then
    let written = Unix.write fd bytes offset length in
    if written = 0 then raise End_of_file
    else write_all_bytes fd bytes (offset + written) (length - written)

let send_marshaled_value_fd fd value =
  let bytes = Marshal.to_bytes value [] in
  write_all_bytes fd bytes 0 (Bytes.length bytes)

let close_fd_noerr fd = try Unix.close fd with _ -> ()

let set_close_on_exec_noerr fd = try Unix.set_close_on_exec fd with _ -> ()

let create_pipe_noerr () =
  let read_fd, write_fd = Unix.pipe () in
  List.iter set_close_on_exec_noerr [ read_fd; write_fd ];
  (read_fd, write_fd)

let write_string_fd fd text =
  let bytes = Bytes.of_string text in
  write_all_bytes fd bytes 0 (Bytes.length bytes)

let string_contains_substring ~needle text =
  let needle_len = String.length needle in
  let text_len = String.length text in
  let rec loop i =
    if needle_len = 0 then true
    else if i + needle_len > text_len then false
    else if String.sub text i needle_len = needle then true
    else loop (i + 1)
  in
  loop 0
