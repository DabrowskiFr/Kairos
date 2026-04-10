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

(** Why3 proof execution and task-level analysis.

    In this module, a {{!Why3.Task.task}task} is one elementary proof
    obligation handled by Why3 (hypotheses + one goal).

    {e Normalized tasks} are the obligations obtained after Why3 normalization
    (notably VC splitting), so each resulting task is an atomic goal that can be
    proved, dumped, diagnosed, and traced independently. *)

(** Per-goal proof result returned by batch proving.

    Fields:
    - [goal_name]: normalized Why3 goal identifier.
    - [answer]: typed Why3 prover answer.
    - [time_s]: elapsed solver time in seconds for this goal.
    - [dump_path]: optional path to dumped failing SMT script.
    - [source]: provenance/source label attached to the goal. *)
type goal_proof_result = {
  goal_name : string;
  answer : Why3.Call_provers.prover_answer;
  time_s : float;
  dump_path : string option;
  source : string;
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

(** Convert a Why3 prover answer into the stable Kairos status string.

    @param answer
      Typed answer returned by Why3.
    @return
      One of [valid], [invalid], [timeout], [unknown], [oom], [failure]. *)
val prover_answer_to_status : Why3.Call_provers.prover_answer -> string

(** Run proof on normalized tasks built from a Why3 parse tree.

    @param timeout
      Per-goal timeout in seconds.
    @param should_cancel
      Cooperative cancellation callback, polled between goals.
    @param on_goal_start
      Optional callback fired when one goal starts. Defaults to a no-op.
    @param on_goal_done
      Optional callback fired when one goal completes. Defaults to a no-op.
    @param ptree
      WhyML parse tree to normalize and prove.
    @return
      One entry per proven goal, in normalized goal order. *)
val prove_ptree_with_events :
  ?timeout:int ->
  ?should_cancel:(unit -> bool) ->
  ?on_goal_start:(goal_start_event -> unit) ->
  ?on_goal_done:(goal_done_event -> unit) ->
  Why3.Ptree.mlw_file ->
  goal_proof_result list

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
