(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

module Contract = Kairos_proof_contract.Proof_backend_contract

type progress = { emit : Pipeline_types.goal_info -> unit }

type t = {
  result_index : int;
  result_goal_name : string;
  result_status : string;
  result_time_s : float;
  result_timing : Contract.goal_timing;
  result_dump_path : string option;
  result_vcid : string option;
  result_probe : Contract.solver_probe option;
}

val pending : index:int -> goal_name:string -> vcid:string option -> t

val execute :
  progress:progress option ->
  cfg:Pipeline_types.config ->
  whyml_text:string ->
  split_vc:bool ->
  emit_vc_text:bool ->
  emit_smt_text:bool ->
  diagnose_nonvalid:bool ->
  Contract.execution_response

val results_of_response :
  vc_ids_ordered:int list -> Contract.execution_response -> t list

val vc_ids_from_result_indices : t list -> int list
val to_goal_info : t -> Pipeline_types.goal_info
