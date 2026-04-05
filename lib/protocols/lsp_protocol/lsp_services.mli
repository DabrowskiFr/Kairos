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

(** High-level LSP services built on top of the Kairos pipeline. *)

type diagnostic = {
  line : int;
  col : int;
  severity : int;
  source : string;
  message : string;
}

val diagnostics_for_text : uri:string -> text:string -> diagnostic list

type outline_sections = {
  nodes : (string * int) list;
  transitions : (string * int) list;
  contracts : (string * int) list;
}

val outline_sections_of_text : string -> outline_sections
val yojson_of_outline_sections : outline_sections -> Yojson.Safe.t

type goal_tree_entry = {
  idx : int;
  goal : string;
  status : string;
  time_s : float;
  dump_path : string option;
  source : string;
  vcid : string option;
}

type goal_tree_transition = {
  transition : string;
  source : string;
  succeeded : int;
  total : int;
  items : goal_tree_entry list;
}

type goal_tree_node = {
  node : string;
  source : string;
  succeeded : int;
  total : int;
  transitions : goal_tree_transition list;
}

val goals_tree_final :
  goals:Pipeline_types.goal_info list ->
  vc_sources:(int * string) list ->
  vc_text:string ->
  goal_tree_node list

val goals_tree_pending :
  goal_names:string list ->
  vc_ids:int list ->
  vc_sources:(int * string) list ->
  goal_tree_node list

val yojson_of_goals_tree : goal_tree_node list -> Yojson.Safe.t

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  vars : string list;
}

val parse_program_from_text : string -> Ast.program option
val semantic_symbols_of_program : Ast.program -> semantic_symbols
val symbol_kind : semantic_symbols -> string -> string option
val identifier_occurrences : string -> string -> (int * int * int) list
val identifier_at : string -> int -> int -> string option
val first_definition_position : text:string -> ident:string -> symbols:semantic_symbols -> (int * int * int) option

type document_symbol = { name : string; line : int; character : int }

val document_symbols_for_text : string -> document_symbol list
val completion_items_for_text : string -> string list
val format_text : string -> string
