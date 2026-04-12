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

module Usecases = Verification_flow_usecases.Make (Verification_runtime_adapters.Ports)

let build_snapshot = Verification_runtime_adapters.Ports.Snapshot.build_snapshot
let instrumentation_pass = Usecases.instrumentation_pass
let why_pass = Usecases.why_pass
let obligations_pass = Usecases.obligations_pass
let normalized_program = Usecases.normalized_program
let ir_pretty_dump = Usecases.ir_pretty_dump
let run = Usecases.run
let run_with_callbacks = Usecases.run_with_callbacks
let compile_object = Verification_runtime_adapters.compile_object
