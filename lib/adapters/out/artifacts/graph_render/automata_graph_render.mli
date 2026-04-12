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

(** Graph renderers for require/ensures automata and their synchronized product. *)
open Core_syntax
(** One DOT graph paired with its human-readable labels. *)
type graph = {
  dot : string;
  labels : string;
}

(** Render only the ensures automaton. *)
val render_ensures_automaton :
  node_name:ident ->
  analysis:Temporal_automata.node_data ->
  graph

(** Render only the require automaton. *)
val render_require_automaton :
  node_name:ident ->
  analysis:Temporal_automata.node_data ->
  graph

(** Render only the product graph (merged by destination states). *)
val render_product :
  node_name:ident ->
  analysis:Temporal_automata.node_data ->
  graph

(** Render the program control automaton. *)
val render_program_automaton :
  node_name:ident ->
  node:Ast.node ->
  graph
