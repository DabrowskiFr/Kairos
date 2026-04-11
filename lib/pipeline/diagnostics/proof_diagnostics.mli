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

(** Proof diagnostics helpers used by pipeline outputs. *)

val diagnostic_for_trace :
  status:string ->
  goal_text:string ->
  native_core:Why_native_probe.native_unsat_core option ->
  native_probe:Why_native_probe.native_solver_probe option ->
  Pipeline_types.proof_diagnostic

val generic_diagnostic_for_status :
  status:string ->
  Pipeline_types.proof_diagnostic ->
  Pipeline_types.proof_diagnostic

val apply_goal_results_to_outputs :
  out:Pipeline_types.outputs ->
  goal_results:(int * string * string * float * string option * string * string option) list ->
  Pipeline_types.outputs
