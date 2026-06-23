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

(** Construction of per-goal proof results from Why3 prover events. *)

type progress = { emit : Pipeline_types.goal_info -> unit }

type t = {
  result_index : int;
  result_goal_name : string;
  result_status : string;
  result_time_s : float;
  result_timing : Why_contract_prove.goal_timing;
  result_dump_path : string option;
  result_vcid : string option;
}

val pending : index:int -> goal_name:string -> vcid:string option -> t

val of_normalized_tasks :
  progress:progress option ->
  cfg:Pipeline_types.config ->
  vc_ids_ordered:int list ->
  normalized_tasks:Why3.Task.task list ->
  t list

val of_module_ptrees_fast :
  cfg:Pipeline_types.config ->
  module_ptrees:Why3.Ptree.mlw_file list ->
  t list

val vc_ids_from_result_indices : t list -> int list

val to_goal_info : t -> Pipeline_types.goal_info
