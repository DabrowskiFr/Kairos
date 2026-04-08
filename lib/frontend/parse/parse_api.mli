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

(** Public parsing entry points for the frontend. *)

(** Parse a file and keep the explicit import declarations alongside the node
    program. *)
val parse_source_file_with_info : string -> Source_file.t * Parse_info.t

(** Parse a file and return only the node program. *)
val parse_file : string -> Ast.program

(** Same as {!parse_file}, but also return frontend parse metadata. *)
val parse_file_with_info : string -> Ast.program * Parse_info.t
