(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Shared utilities for the C backend. *)

module StringSet : Set.S with type elt = string

val ( let* ) : ('a, 'e) result -> ('a -> ('b, 'e) result) -> ('b, 'e) result
val errorf : ('a, unit, string, ('b, string) result) format4 -> 'a
val map_result : ('a -> ('b, 'e) result) -> 'a list -> ('b list, 'e) result
val concat_map_result :
  ('a -> ('b list, 'e) result) -> 'a list -> ('b list, 'e) result

val line : int -> string -> string
val blank : string
val join_lines : string list -> string
