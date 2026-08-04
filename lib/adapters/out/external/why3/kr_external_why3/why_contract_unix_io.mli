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

(** Small Unix/IPC helpers used by the Why3 proof runner. *)

val write_all_bytes : Unix.file_descr -> bytes -> int -> int -> unit
val send_marshaled_value_fd : Unix.file_descr -> 'a -> unit
val close_fd_noerr : Unix.file_descr -> unit
val set_close_on_exec_noerr : Unix.file_descr -> unit
val create_pipe_noerr : unit -> Unix.file_descr * Unix.file_descr
val write_string_fd : Unix.file_descr -> string -> unit
val string_contains_substring : needle:string -> string -> bool
