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

(** Native SMT probing helpers (diagnostic-only path).

    This module is intentionally separate from proof execution:
    it provides native solver replay utilities used for diagnostics. *)

(** Native unsat-core payload from the underlying SMT solver. *)
type native_unsat_core = {
  solver : string;
  hypothesis_ids : int list;
  smt_text : string;
}

(** Native probing payload for one goal, including optional model text. *)
type native_solver_probe = {
  solver : string;
  status : string;
  detail : string option;
  model_text : string option;
  smt_text : string;
}

(** Request a native unsat-core for one targeted goal.

    @param timeout
      Solver timeout in seconds.
    @param ptree
      WhyML parse tree containing the target goal.
    @param goal_index
      Zero-based index in normalized goal order.
    @return
      [Some core] when solver output provides an unsat core, [None] otherwise. *)
val native_unsat_core_for_goal_of_ptree :
  ?timeout:int ->
  ptree:Why3.Ptree.mlw_file ->
  goal_index:int ->
  unit ->
  native_unsat_core option

(** Probe one goal through the native SMT solver.

    @param timeout
      Solver timeout in seconds.
    @param ptree
      WhyML parse tree containing the target goal.
    @param goal_index
      Zero-based index in normalized goal order.
    @return
      [Some probe] with solver status/details (and optional model for SAT),
      [None] when the goal cannot be targeted. *)
val native_solver_probe_for_goal_of_ptree :
  ?timeout:int ->
  ptree:Why3.Ptree.mlw_file ->
  goal_index:int ->
  unit ->
  native_solver_probe option
