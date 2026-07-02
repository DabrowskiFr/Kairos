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

(** Structured frontend failures.

    The parser, elaborator, and model validators use this exception internally
    to keep their historical direct style while preserving an explicit error
    class at the application boundary. *)

type kind =
  | Parse
  | Elaboration
  | Type
  | Well_formedness
  | Internal

type t = {
  kind : kind;
  message : string;
}

exception Error of t

val raise_error : kind -> string -> 'a
val parse : string -> 'a
val elaboration : string -> 'a
val type_error : string -> 'a
val well_formedness : string -> 'a
val internal : string -> 'a
