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

(* Monitor state constructor name for a given index (e.g. Mon0, Mon1). *)
val monitor_state_ctor : int -> string

(* Instrument a node with monitor support (standard compilation). *)
val transform_node : build:Monitor_generation.monitor_generation_build -> Ast.node -> Ast.node

(* Instrument a node, but only for monitor‑specific code paths. *)
val transform_node_monitor :
  build:Monitor_generation.monitor_generation_build -> Ast.node -> Ast.node

(* Instrument a node and return detailed monitor metadata. *)
val transform_node_monitor_with_info :
  build:Monitor_generation.monitor_generation_build ->
  Ast.node ->
  Ast.node * Stage_info.monitor_info
