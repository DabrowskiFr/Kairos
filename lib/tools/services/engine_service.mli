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

(** Unified engine selector used by CLI, LSP, and IDE. *)

type engine = Default

val engine_of_string : string -> engine option
val string_of_engine : engine -> string
val normalize : engine -> engine

val instrumentation_pass :
  engine:engine -> generate_png:bool -> input_file:string ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result

val why_pass :
  engine:engine ->
  input_file:string ->
  (Pipeline_types.why_outputs, Pipeline_types.error) result

val obligations_pass :
  engine:engine ->
  prover:string ->
  input_file:string ->
  (Pipeline_types.obligations_outputs, Pipeline_types.error) result

val normalized_program :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result
val ir_pretty_dump :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result

val compile_object :
  engine:engine -> input_file:string -> (Kairos_object.t, Pipeline_types.error) result

val eval_pass :
  engine:engine -> input_file:string -> trace_text:string -> with_state:bool -> with_locals:bool ->
  (string, Pipeline_types.error) result

val run :
  engine:engine -> Pipeline_types.config ->
  (Pipeline_types.outputs, Pipeline_types.error) result

val run_with_callbacks :
  engine:engine ->
  should_cancel:(unit -> bool) ->
  Pipeline_types.config ->
  on_outputs_ready:(Pipeline_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (Pipeline_types.outputs, Pipeline_types.error) result
