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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Execute application verification use-cases for the LSP server. *)

val instrumentation_pass :
  Kairos_lsp_protocol.instrumentation_pass_request ->
  (Kairos_lsp_protocol.automata_outputs, string) result

val why_pass :
  Kairos_lsp_protocol.why_pass_request ->
  (Kairos_lsp_protocol.why_outputs, string) result

val obligations_pass :
  Kairos_lsp_protocol.obligations_pass_request ->
  (Kairos_lsp_protocol.obligations_outputs, string) result

val normalized_program :
  Kairos_lsp_protocol.text_dump_request ->
  (string, string) result

val ir_pretty_dump :
  Kairos_lsp_protocol.text_dump_request ->
  (string, string) result

val run :
  engine:Engine_service.engine ->
  Kairos_lsp_protocol.config ->
  (Kairos_lsp_protocol.outputs, string) result

val run_with_callbacks :
  engine:Engine_service.engine ->
  should_cancel:(unit -> bool) ->
  Kairos_lsp_protocol.config ->
  on_outputs_ready:(Kairos_lsp_protocol.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string option -> unit) ->
  (Kairos_lsp_protocol.outputs, string) result
