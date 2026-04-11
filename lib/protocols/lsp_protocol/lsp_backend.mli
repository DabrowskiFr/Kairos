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

val pipeline_config_of_protocol : Lsp_protocol.config -> Pipeline_types.config

val instrumentation_pass :
  Lsp_protocol.instrumentation_pass_request ->
  (Lsp_protocol.automata_outputs, string) result

val why_pass :
  Lsp_protocol.why_pass_request ->
  (Lsp_protocol.why_outputs, string) result

val obligations_pass :
  Lsp_protocol.obligations_pass_request ->
  (Lsp_protocol.obligations_outputs, string) result

val kobj_summary :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val kobj_clauses :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val kobj_product :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val kobj_contracts :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val normalized_program :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val ir_pretty_dump :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val dot_png_from_text :
  Lsp_protocol.dot_png_from_text_request ->
  string option

val run :
  engine:Engine_service.engine ->
  Lsp_protocol.config ->
  (Lsp_protocol.outputs, string) result

val run_with_callbacks :
  engine:Engine_service.engine ->
  should_cancel:(unit -> bool) ->
  Lsp_protocol.config ->
  on_outputs_ready:(Lsp_protocol.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string option -> unit) ->
  (Lsp_protocol.outputs, string) result
