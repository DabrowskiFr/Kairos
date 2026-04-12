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

(** Public parsing entry points and source-level parse data.

    This module is the single public API of the parsing layer. It exposes:
    - the parsed source shape (imports + nodes),
    - parse diagnostics,
    - parsing functions for text buffers. *)

(** One syntactic import declaration. *)
type import_decl = {
  import_path : string;
  import_loc : Loc.loc option;
}

(** Parsed source file, before import resolution/expansion. *)
type source = {
  imports : import_decl list;
  nodes : Ast.program;
}

(** Paths referenced by explicit imports, in source order. *)
val imported_paths : source -> string list

(** One parse error with optional source location. *)
type parse_error = {
  loc : Loc.loc option;
  message : string;
}

(** Parse diagnostics bundle attached to one parsed source. *)
type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

(** Parse source text and keep explicit imports with parse diagnostics. *)
val parse_source_text_with_info :
  filename:string ->
  text:string ->
  source * parse_info
