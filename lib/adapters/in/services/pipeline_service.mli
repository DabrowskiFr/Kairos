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

(** Pipeline orchestration service built on top of specialized pipeline modules. *)

type goal_info = string * string * float * string option * string option
type stage_meta = (string * (string * string) list) list

type automata_dump_data = {
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_text : string;
  product_dot : string;
  canonical_text : string;
  canonical_dot : string;
  obligations_map_text : string;
}

type obligations_dump_data = {
  vc_text : string;
  smt_text : string;
}

type run_dump_data = {
  why_text : string;
  vc_text : string;
  smt_text : string;
  stage_meta : stage_meta;
  goals : goal_info list;
}

val instrumentation_pass :
  generate_png:bool ->
  input_file:string ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result

val why_pass :
  input_file:string ->
  (Pipeline_types.why_outputs, Pipeline_types.error) result

val obligations_pass :
  input_file:string ->
  (Pipeline_types.obligations_outputs, Pipeline_types.error) result

val automata_dump_data :
  input_file:string -> (automata_dump_data, Pipeline_types.error) result

val why_text_dump :
  input_file:string -> (string, Pipeline_types.error) result

val obligations_dump_data :
  input_file:string -> (obligations_dump_data, Pipeline_types.error) result

val run_dump_data :
  input_file:string ->
  timeout_s:int ->
  prove:bool ->
  generate_vc_text:bool ->
  generate_smt_text:bool ->
  (run_dump_data, Pipeline_types.error) result

val kobj_summary :
  input_file:string -> (string, Pipeline_types.error) result

val kobj_clauses :
  input_file:string -> (string, Pipeline_types.error) result

val kobj_product :
  input_file:string -> (string, Pipeline_types.error) result

val kobj_contracts :
  input_file:string -> (string, Pipeline_types.error) result

val normalized_program : input_file:string -> (string, Pipeline_types.error) result
val ir_pretty_dump : input_file:string -> (string, Pipeline_types.error) result

val run : Pipeline_types.config -> (Pipeline_types.outputs, Pipeline_types.error) result

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  Pipeline_types.config ->
  on_outputs_ready:(Pipeline_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string option -> unit) ->
  (Pipeline_types.outputs, Pipeline_types.error) result
