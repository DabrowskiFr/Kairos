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

(** Internal parsing entry points and source-level parse data.

    Both entry points consume text rather than opening a file, so they can
    analyze unsaved editor buffers. One stops at the surface AST; the other also
    runs frontend elaboration. Parse failures are raised as
    [Kx_frontend_error.Error]. *)

(** Import retained after resolving its declaration-only source file. *)
type import_decl = {
  import_path : string;
  import_loc : Kx_syntax_common.loc option;
}

(** Source file after imports have been resolved and surface constructs elaborated. *)
type source = {
  imports : import_decl list;
  type_decls : Kx_core_syntax.enum_decl list; (** Shared enum declarations. *)
  function_decls : Kx_core_syntax.pure_function_decl list;
      (** Shared pure-function declarations. *)
  nodes : Kx_core_ast.program; (** Elaborated program nodes. *)
}

(** Parsed surface source before frontend elaboration. *)
type surface_source = Kx_surface_ast.source

val imported_paths : source -> string list
(** Return explicit import paths in source order. *)

(** One parse error with optional source location. *)
type parse_error = {
  loc : Kx_syntax_common.loc option; (** Structured location when one is available. *)
  message : string; (** Human-readable parser diagnostic. *)
}

(** Parse diagnostics bundle attached to one parsed source. *)
type parse_info = {
  source_path : string option; (** Logical filename associated with the text. *)
  text_hash : string option; (** Digest of the analyzed text. *)
  parse_errors : parse_error list;
      (** Structured parser diagnostics. With the current fail-fast parser,
          this is empty whenever parsing returns normally. *)
  warnings : string list; (** Non-fatal frontend diagnostics. *)
}

(** Parse and elaborate a text buffer into declarations and program nodes. *)
val parse_source_text_with_info :
  filename:string ->
  text:string ->
  source * parse_info

(** Parse a text buffer into the surface AST without running elaboration. *)
val parse_surface_text_with_info :
  filename:string ->
  text:string ->
  surface_source * parse_info

(** Serialize the surface AST as human-readable debug JSON. *)
val surface_source_to_json : surface_source -> string

(** Serialize the elaborated source as human-readable debug JSON. *)
val source_to_json : source -> string
