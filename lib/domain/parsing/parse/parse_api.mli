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

(** Parse source text and keep the explicit import declarations alongside the node
    program. *)
val parse_source_text_with_info :
  filename:string ->
  text:string ->
  Source_file.t * Parse_info.t

(** Parse source text and return only the node program. *)
val parse_text :
  filename:string ->
  text:string ->
  Ast.program

(** Same as {!parse_text}, but also return frontend parse metadata. *)
val parse_text_with_info :
  filename:string ->
  text:string ->
  Ast.program * Parse_info.t
