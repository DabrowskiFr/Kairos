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

(** High-level orchestration for full compilation/proof runs. *)

val run :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error) result) ->
  build_outputs:
    (cfg:Pipeline_types.config ->
    asts:Pipeline_types.ast_stages ->
    infos:Pipeline_types.stage_infos ->
    (Pipeline_types.outputs, Pipeline_types.error) result) ->
  Pipeline_types.config ->
  (Pipeline_types.outputs, Pipeline_types.error) result

val run_with_callbacks :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error) result) ->
  build_outputs:
    (cfg:Pipeline_types.config ->
    asts:Pipeline_types.ast_stages ->
    infos:Pipeline_types.stage_infos ->
    (Pipeline_types.outputs, Pipeline_types.error) result) ->
  should_cancel:(unit -> bool) ->
  Pipeline_types.config ->
  on_outputs_ready:(Pipeline_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string option -> unit) ->
  (Pipeline_types.outputs, Pipeline_types.error) result
