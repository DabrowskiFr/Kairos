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

(* State constructor name for a given index (e.g. Aut0, Aut1). *)
val state_ctor : int -> string

(* Instrument a node (AST compatibility wrapper). *)
val transform_node : build:Automata_generation.automata_build -> Ast.node -> Ast.node

(* Primary API: instrument an abstract node and return detailed metadata. *)
val transform_abstract_node_with_info :
  build:Automata_generation.automata_build ->
  ?nodes:Abstract_model.node list ->
  Abstract_model.node ->
  Abstract_model.node * Stage_info.instrumentation_info

(* AST compatibility wrapper around the primary abstract API. *)
val transform_node_with_info :
  build:Automata_generation.automata_build ->
  ?nodes:Ast.program ->
  Ast.node ->
  Ast.node * Stage_info.instrumentation_info
