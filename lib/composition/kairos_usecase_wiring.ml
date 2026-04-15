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

let ( let* ) = Result.bind

module Frontend = struct
  let parse_input = Kairos_frontend.parse_input
end

module Instrumentation = struct
  let instrumentation_pass ~generate_png ~input_file =
    let* frontend = Frontend.parse_input ~input_file in
    let* snapshot = Verification_runtime_adapters.Snapshot.build_snapshot ~frontend in
    Verification_runtime_adapters.instrumentation_from_snapshot ~generate_png ~snapshot
end

module Ports = struct
  type snapshot = Runtime_snapshot.pipeline_snapshot

  module Frontend = Frontend
  module Snapshot = Verification_runtime_adapters.Snapshot
  module Outputs = Verification_runtime_adapters.Outputs
  module Instrumentation = Instrumentation
  module Why_text = Verification_runtime_adapters.Why_text
  module Obligations = Verification_runtime_adapters.Obligations
  module Ir_render = Verification_runtime_adapters.Ir_render
  module Timing = Verification_runtime_adapters.Timing
  module Proof_events = Verification_runtime_adapters.Proof_events
end

let compile_object ~input_file : (Kairos_object.t, Pipeline_types.error) result =
  let* frontend = Frontend.parse_input ~input_file in
  let* snapshot = Verification_runtime_adapters.Snapshot.build_snapshot ~frontend in
  Verification_runtime_adapters.compile_object_from_snapshot ~input_file ~snapshot
