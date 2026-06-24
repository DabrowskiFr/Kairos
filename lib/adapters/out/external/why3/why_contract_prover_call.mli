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

(** Low-level execution of prepared Why3 proof tasks.

    This module owns the mechanics of preparing, printing, launching, waiting
    for, and optionally falling back from one Why3 prover call. It deliberately
    does not schedule batches or workers. *)

type prover_handle = {
  driver : Why3.Driver.driver;
  command : string;
}

val goal_name_of_prepared_task : Why3.Task.task -> string

val duplicate_detail_for_goal :
  goal_name:string ->
  Why_contract_proof_types.goal_proof_result ->
  Why_contract_proof_types.goal_proof_result

val prepare_task_with_timing :
  driver:Why3.Driver.driver -> Why3.Task.task -> Why3.Task.task

val print_prepared_task :
  handle:prover_handle ->
  prepared:Why3.Task.task ->
  Buffer.t * string * Why3.Printer.printing_info * float

val prove_one_task_with_details :
  why3_main:Why3.Whyconf.main ->
  limits:Why3.Call_provers.resource_limits ->
  primary:prover_handle ->
  fallback:prover_handle option ->
  dump_failed_smt:bool ->
  task_index:int ->
  prepared:Why3.Task.task ->
  goal_name:string ->
  Why_contract_proof_types.goal_proof_result

val prove_printed_prepared_task :
  why3_main:Why3.Whyconf.main ->
  limits:Why3.Call_provers.resource_limits ->
  primary:prover_handle ->
  fallback:prover_handle option ->
  persistent_z3:Why_contract_persistent_z3.runner option ->
  dump_failed_smt:bool ->
  task_index:int ->
  prepared:Why3.Task.task ->
  goal_name:string ->
  base_timing:Why_contract_proof_types.goal_timing ->
  primary_buffer:Buffer.t ->
  printing_info:Why3.Printer.printing_info ->
  Why_contract_proof_types.goal_proof_result
