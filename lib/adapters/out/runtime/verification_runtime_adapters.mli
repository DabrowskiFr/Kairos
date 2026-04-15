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

(** Concrete outgoing adapter modules (snapshot, outputs, Why, obligations, etc.). *)

module Snapshot : Application_ports.SNAPSHOT_PORT with type snapshot = Runtime_snapshot.pipeline_snapshot
module Outputs : Application_ports.OUTPUTS_PORT with type snapshot = Runtime_snapshot.pipeline_snapshot
module Why_text : Application_ports.WHY_TEXT_PORT with type snapshot = Runtime_snapshot.pipeline_snapshot
module Obligations : Application_ports.OBLIGATIONS_PORT with type snapshot = Runtime_snapshot.pipeline_snapshot
module Ir_render : Application_ports.IR_RENDER_PORT with type snapshot = Runtime_snapshot.pipeline_snapshot
module Timing : Application_ports.TIMING_PORT
module Proof_events :
  Application_ports.PROOF_EVENTS_PORT with type snapshot = Runtime_snapshot.pipeline_snapshot

(** Build instrumentation artifacts from an already prepared snapshot. *)
val instrumentation_from_snapshot :
  generate_png:bool ->
  snapshot:Runtime_snapshot.pipeline_snapshot ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result

(** Build a [.kobj] object from an already prepared snapshot. *)
val compile_object_from_snapshot :
  input_file:string ->
  snapshot:Runtime_snapshot.pipeline_snapshot ->
  (Kairos_object.t, Pipeline_types.error) result
