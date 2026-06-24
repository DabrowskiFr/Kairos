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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Shared utilities for diagnostic cost reports. *)

module Json : module type of Yojson.Safe
module StringMap : Map.S with type key = string
module StringSet : Set.S with type elt = string

val json_int : int -> Json.t
val json_float : float -> Json.t
val json_string : string -> Json.t
val json_bool : bool -> Json.t
val json_list : ('a -> Json.t) -> 'a list -> Json.t
val json_assoc : (string * Json.t) list -> Json.t
val json_opt : ('a -> Json.t) -> 'a option -> Json.t

val count_if : ('a -> bool) -> 'a list -> int
val sum_int : int list -> int
val max_int : int list -> int
val average_int : int list -> float
val top_values : int -> 'a list -> 'a list
val top_string_values : int -> string list -> string list
val truncate_string : int -> string -> string
val starts_with : prefix:string -> string -> bool
val contains_substring : string -> string -> bool
