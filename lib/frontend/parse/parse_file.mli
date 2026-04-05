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

(** File-based parsing helpers built on top of the lexer and parser. *)

(** Parse one source file into the import-aware representation and collect
    parse metadata. *)
val parse_source_file_with_info : string -> Source_file.t * Stage_info.parse_info

(** Parse one source file and discard explicit imports, keeping only the node
    program. *)
val parse_file : string -> Ast.program

(** Parse one source file into an [Ast.program] together with parse metadata. *)
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
