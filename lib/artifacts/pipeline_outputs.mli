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

(** Full output assembly for the imported/main pipeline. *)

val stage_meta :
  Pipeline_types.stage_infos -> (string * (string * string) list) list

val instrumentation_diag_texts :
  Pipeline_types.stage_infos ->
  string * string * string * string * string * string * string * string * string * string * string * string
  * string * string * string

val program_automaton_texts : Pipeline_types.ast_stages -> string * string

val build_outputs :
  cfg:Pipeline_types.config ->
  asts:Pipeline_types.ast_stages ->
  infos:Pipeline_types.stage_infos ->
  (Pipeline_types.outputs, Pipeline_types.error) result
