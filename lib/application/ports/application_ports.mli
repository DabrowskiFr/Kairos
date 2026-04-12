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

(** Application-level ports for Kairos use-cases.

    This module defines the dependency inversion boundary used by
    {!Verification_flow_usecases}.  The use-case layer depends on these abstract
    signatures only; concrete implementations are provided by outgoing adapters.
*)

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

(** One goal result reported by the proof-events port.

    Tuple layout:
    - goal index in the emitted VC order,
    - goal name,
    - textual status,
    - solver time (seconds),
    - optional dump path,
    - optional VC identifier.
*)

type goal_result = int * string * string * float * string option * string option

(** Port producing an immutable pipeline snapshot from an input file. *)

module type SNAPSHOT_PORT = sig
  (** Opaque snapshot type shared by all other ports. *)

  type snapshot

  (** Build a snapshot from [input_file].

      Returns [Error _] when parsing or stage preparation fails.
  *)

  val build_snapshot :
    input_file:string ->
    (snapshot, Pipeline_types.error) result
end

(** Port assembling final pipeline outputs from a prepared snapshot. *)

module type OUTPUTS_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Run output assembly for [cfg] on [snapshot]. *)

  val build_outputs :
    cfg:Pipeline_types.config ->
    snapshot:snapshot ->
    (Pipeline_types.outputs, Pipeline_types.error) result
end

(** Port exposing the automata/instrumentation dump pass. *)

module type INSTRUMENTATION_PORT = sig
  (** Run instrumentation artifacts generation for [input_file].

      When [generate_png] is true, PNG rendering is attempted for DOT graphs.
  *)

  val instrumentation_pass :
    generate_png:bool ->
    input_file:string ->
    (Pipeline_types.automata_outputs, Pipeline_types.error) result
end

(** Port generating Why text artifacts from a snapshot. *)

module type WHY_TEXT_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Produce Why text outputs for [snapshot]. *)

  val why_text :
    snapshot:snapshot ->
    Pipeline_types.why_outputs
end

(** Port generating VC/SMT obligations from a snapshot. *)

module type OBLIGATIONS_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Produce VC and SMT textual obligations for [snapshot]. *)

  val obligations :
    snapshot:snapshot ->
    Pipeline_types.obligations_outputs
end

(** Port exposing textual renderings of the normalized IR. *)

module type IR_RENDER_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Render the normalized program view for [snapshot]. *)

  val normalized_program : snapshot:snapshot -> string
  (** Render the proof-oriented pretty IR view for [snapshot]. *)

  val pretty_program : snapshot:snapshot -> string
end

(** Port exposing external timing counters used by use-cases. *)

module type TIMING_PORT = sig
  (** Opaque timing snapshot captured by the concrete adapter. *)

  type snapshot

  (** Capture timing counters at current instant. *)

  val snapshot : unit -> snapshot
  (** Compute elapsed counters between [before] and [after_]. *)

  val diff : before:snapshot -> after_:snapshot -> timing_counters
end

(** Port executing proof replay with per-goal callbacks. *)

module type PROOF_EVENTS_PORT = sig
  (** Opaque snapshot type shared across ports. *)

  type snapshot

  (** Replay proof on [snapshot], emitting [on_goal_done] events in VC order.

      [vc_ids_ordered] maps event indexes to stable VC identifiers.
  *)

  val prove_with_events :
    timeout_s:int ->
    should_cancel:(unit -> bool) ->
    snapshot:snapshot ->
    vc_ids_ordered:int list ->
    on_goal_done:(goal_result -> unit) ->
    goal_result list
end

(** Aggregate of all ports required by pipeline use-cases. *)

module type PORTS = sig
  (** Opaque snapshot type threaded through all sub-ports. *)

  type snapshot

  (** Snapshot construction port. *)

  module Snapshot : SNAPSHOT_PORT with type snapshot = snapshot
  (** Final outputs assembly port. *)

  module Outputs : OUTPUTS_PORT with type snapshot = snapshot
  (** Instrumentation dump port. *)

  module Instrumentation : INSTRUMENTATION_PORT
  (** Why text generation port. *)

  module Why_text : WHY_TEXT_PORT with type snapshot = snapshot
  (** VC/SMT obligations generation port. *)

  module Obligations : OBLIGATIONS_PORT with type snapshot = snapshot
  (** IR text rendering port. *)

  module Ir_render : IR_RENDER_PORT with type snapshot = snapshot
  (** Timing counters port. *)

  module Timing : TIMING_PORT
  (** Proof events replay port. *)

  module Proof_events : PROOF_EVENTS_PORT with type snapshot = snapshot
end
