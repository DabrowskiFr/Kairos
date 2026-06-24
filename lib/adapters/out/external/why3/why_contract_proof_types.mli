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

(** Shared proof-result types for the Why3 proof runner.

    This module deliberately contains only typed data exchanged between the
    prover runner, workers, and runtime reporting layer. It does not know how
    to prepare, print, schedule, or prove Why3 tasks. *)

(** Per-goal backend timing.  The solver time is the prover-reported CPU time;
    the other fields are wall-clock time observed by Kairos around the Why3
    driver/prover calls. *)
type goal_timing = {
  prepare_s : float;
  print_s : float;
  spawn_s : float;
  wait_s : float;
  solver_s : float;
}

(** Per-goal proof result returned by batch proving.

    Fields:
    - [goal_name]: normalized Why3 goal identifier.
    - [prover_result]: full typed Why3 prover result for this goal.
    - [dump_path]: optional path to dumped failing SMT script. *)
type goal_proof_result = {
  goal_name : string;
  prover_result : Why3.Call_provers.prover_result;
  dump_path : string option;
  timing : goal_timing;
}

(** Event payload emitted when one goal starts.

    Fields:
    - [goal_index]: zero-based index in normalized goal order.
    - [goal_name]: Why3 goal identifier. *)
type goal_start_event = {
  goal_index : int;
  goal_name : string;
}

(** Event payload emitted when one goal is finished.

    Fields:
    - [goal_index]: zero-based index in normalized goal order.
    - [result]: structured proof outcome for that goal. *)
type goal_done_event = {
  goal_index : int;
  result : goal_proof_result;
}

val zero_goal_timing : goal_timing
val add_goal_timing : goal_timing -> goal_timing -> goal_timing
val goal_timing_with_prepare : float -> goal_timing
