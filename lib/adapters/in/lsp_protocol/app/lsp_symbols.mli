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

(** Symbol extraction and lookup helpers for LSP navigation features. *)

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  vars : string list;
}

type document_symbol = { name : string; line : int; character : int }

val parse_program_from_text : string -> Kx_ast.program option
val semantic_symbols_of_program : Kx_ast.program -> semantic_symbols
val symbol_kind : semantic_symbols -> string -> string option
val identifier_occurrences : string -> string -> (int * int * int) list
val identifier_at : string -> int -> int -> string option

val first_definition_position :
  text:string ->
  ident:string ->
  symbols:semantic_symbols ->
  (int * int * int) option

val document_symbols_for_text : string -> document_symbol list
