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

(** Application use-cases for the Kairos pipeline.

    These use-cases only depend on abstract ports from {!Application_ports}. *)

module Make (P : Application_ports.PORTS) : sig
  (** Run the instrumentation/artifacts pass on one source file. *)

  val instrumentation_pass :
    generate_png:bool ->
    input_file:string ->
    (Pipeline_types.automata_outputs, Pipeline_types.error) result

  (** Generate Why text outputs on one source file. *)

  val why_pass :
    input_file:string ->
    (Pipeline_types.why_outputs, Pipeline_types.error) result

  (** Generate VC/SMT obligations on one source file. *)

  val obligations_pass :
    input_file:string ->
    (Pipeline_types.obligations_outputs, Pipeline_types.error) result

  (** Render the normalized IR textual view for one source file. *)

  val normalized_program : input_file:string -> (string, Pipeline_types.error) result
  (** Render the proof-oriented pretty IR textual view for one source file. *)

  val ir_pretty_dump : input_file:string -> (string, Pipeline_types.error) result

  (** Execute the full pipeline according to [config]. *)

  val run : Pipeline_types.config -> (Pipeline_types.outputs, Pipeline_types.error) result

  (** Execute the pipeline with streaming callbacks.

      [on_outputs_ready] is called when static outputs are available.
      [on_goals_ready] receives the ordered goal names and VC ids.
      [on_goal_done] is called once per solved goal.
  *)

  val run_with_callbacks :
    should_cancel:(unit -> bool) ->
    Pipeline_types.config ->
    on_outputs_ready:(Pipeline_types.outputs -> unit) ->
    on_goals_ready:(string list * int list -> unit) ->
    on_goal_done:(int -> string -> string -> float -> string option -> string option -> unit) ->
    (Pipeline_types.outputs, Pipeline_types.error) result
end
