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

val generic_diagnostic_for_status :
  status:string ->
  Pipeline_types.proof_diagnostic ->
  Pipeline_types.proof_diagnostic

(** [apply_goal_results_to_outputs] service entrypoint. *)

val apply_goal_results_to_outputs :
  out:Pipeline_types.outputs ->
  goal_results:(int * string * string * float * string option * string option) list ->
  Pipeline_types.outputs
