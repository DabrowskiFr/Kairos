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

(** Worker-process support for proving batches of Why3 tasks.

    This module owns process spawning, IPC messages, worker shutdown, and task
    distribution. It does not own the public proof API. *)

type worker_to_parent =
  | Worker_started of {
      task_index : int;
      goal_name : string;
      fingerprint : string;
    }
  | Worker_result of {
      task_index : int;
      fingerprint : string;
      result : Why_contract_proof_types.goal_proof_result;
    }
  | Worker_done of
      Why_metrics.worker_snapshot * Why_metrics.snapshot
  | Worker_failed of string * Why_metrics.snapshot

type proof_worker = {
  worker_id : int;
  worker_pid : int;
  worker_input : in_channel;
  worker_fd : Unix.file_descr;
}

val distribute_indexed_tasks : jobs:int -> 'a list -> (int * 'a list) list

val spawn_proof_worker :
  why3_main:Why3.Whyconf.main ->
  limits:Why3.Call_provers.resource_limits ->
  primary:Why_contract_prover_call.prover_handle ->
  fallback:Why_contract_prover_call.fallback_handle option ->
  dump_failed_smt:bool ->
  inherited_workers:proof_worker list ->
  worker_id:int ->
  tasks:(int * Why3.Task.task) list ->
  proof_worker

val read_proof_worker_message : proof_worker -> worker_to_parent option
val wait_for_all_proof_workers : proof_worker list -> unit
val finish_proof_worker : proof_worker -> unit
val select_ready_proof_worker : proof_worker list -> proof_worker option
