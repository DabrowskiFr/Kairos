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

(** Application ports for Kairos use-cases. *)

type timing_counters = {
  spot_s : float;
  spot_calls : int;
  z3_s : float;
  z3_calls : int;
  product_s : float;
  canonical_s : float;
  why_gen_s : float;
  vc_smt_s : float;
}

type goal_result = int * string * string * float * string option * string option

module type SNAPSHOT_PORT = sig
  val build_snapshot :
    input_file:string ->
    (Pipeline_types.pipeline_snapshot, Pipeline_types.error) result
end

module type OUTPUTS_PORT = sig
  val build_outputs :
    cfg:Pipeline_types.config ->
    snapshot:Pipeline_types.pipeline_snapshot ->
    (Pipeline_types.outputs, Pipeline_types.error) result
end

module type INSTRUMENTATION_PORT = sig
  val instrumentation_pass :
    generate_png:bool ->
    input_file:string ->
    (Pipeline_types.automata_outputs, Pipeline_types.error) result
end

module type WHY_TEXT_PORT = sig
  val why_text :
    snapshot:Pipeline_types.pipeline_snapshot ->
    Pipeline_types.why_outputs
end

module type OBLIGATIONS_PORT = sig
  val obligations :
    snapshot:Pipeline_types.pipeline_snapshot ->
    Pipeline_types.obligations_outputs
end

module type IR_RENDER_PORT = sig
  val normalized_program : snapshot:Pipeline_types.pipeline_snapshot -> string
  val pretty_program : snapshot:Pipeline_types.pipeline_snapshot -> string
end

module type TIMING_PORT = sig
  type snapshot

  val snapshot : unit -> snapshot
  val diff : before:snapshot -> after_:snapshot -> timing_counters
end

module type PROOF_EVENTS_PORT = sig
  val prove_with_events :
    timeout_s:int ->
    should_cancel:(unit -> bool) ->
    snapshot:Pipeline_types.pipeline_snapshot ->
    vc_ids_ordered:int list ->
    on_goal_done:(goal_result -> unit) ->
    goal_result list
end

module type PORTS = sig
  module Snapshot : SNAPSHOT_PORT
  module Outputs : OUTPUTS_PORT
  module Instrumentation : INSTRUMENTATION_PORT
  module Why_text : WHY_TEXT_PORT
  module Obligations : OBLIGATIONS_PORT
  module Ir_render : IR_RENDER_PORT
  module Timing : TIMING_PORT
  module Proof_events : PROOF_EVENTS_PORT
end
