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

type goal_timing = {
  prepare_s : float;
  print_s : float;
  spawn_s : float;
  wait_s : float;
  solver_s : float;
}

type goal_proof_result = {
  goal_name : string;
  prover_result : Why3.Call_provers.prover_result;
  dump_path : string option;
  timing : goal_timing;
}

type goal_start_event = {
  goal_index : int;
  goal_name : string;
}

type goal_done_event = {
  goal_index : int;
  result : goal_proof_result;
}

let zero_goal_timing =
  {
    prepare_s = 0.0;
    print_s = 0.0;
    spawn_s = 0.0;
    wait_s = 0.0;
    solver_s = 0.0;
  }

let add_goal_timing left right =
  {
    prepare_s = left.prepare_s +. right.prepare_s;
    print_s = left.print_s +. right.print_s;
    spawn_s = left.spawn_s +. right.spawn_s;
    wait_s = left.wait_s +. right.wait_s;
    solver_s = left.solver_s +. right.solver_s;
  }

let goal_timing_with_prepare prepare_s =
  { zero_goal_timing with prepare_s }
