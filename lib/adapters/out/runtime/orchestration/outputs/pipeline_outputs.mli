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

(** Output assembly for a prepared pipeline snapshot. *)

(** Convert internal stage infos to serialized flow metadata. *)
val flow_meta :
  Pipeline_types.flow_infos -> (string * (string * string) list) list

(** Extract the first node's program automaton DOT and labels text. *)

val program_automaton_texts : Pipeline_types.ast_flow -> string * string

(** Build all public outputs (texts, dots, traces, metadata) for [snapshot]. *)

val build_outputs :
  cfg:Pipeline_types.config ->
  snapshot:Pipeline_types.pipeline_snapshot ->
  (Pipeline_types.outputs, Pipeline_types.error) result
