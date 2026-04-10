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

(** Build instrumentation and automata diagnostic artifacts from staged compilation data. *)

val instrumentation_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error)
    result) ->
  stage_meta:
    (Pipeline_types.stage_infos -> (string * (string * string) list) list) ->
  instrumentation_diag_texts:
    (Pipeline_types.stage_infos ->
    string * string * string * string * string * string * string * string * string) ->
  program_automaton_texts:(Pipeline_types.ast_stages -> string * string) ->
  generate_png:bool ->
  input_file:string ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result
