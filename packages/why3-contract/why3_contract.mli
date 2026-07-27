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

(** Neutral execution contract for generated WhyML.

    The payload contains no Kairos IR and no Why3 value. WhyML is the stable ownership boundary:
    Kairos generates it, while a proof adapter parses it and produces backend-neutral obligations
    and results. *)

type proof_status =
  | Pending
  | Valid
  | Invalid
  | Timeout
  | Unknown of string option
  | Out_of_memory
  | Failure of string option
[@@deriving yojson]

type goal_timing = {
  prepare_s : float;
  print_s : float;
  spawn_s : float;
  wait_s : float;
  solver_s : float;
}
[@@deriving yojson]

type solver_probe = {
  solver : string;
  status : string;
  detail : string option;
  model_text : string option;
  smt_text : string;
}
[@@deriving yojson]

type execution_options = {
  timeout_s : int;
  jobs : int;
  split_vc : bool;
  dump_failed_smt : bool;
  prove : bool;
  emit_vc_text : bool;
  emit_smt_text : bool;
  diagnose_nonvalid : bool;
}
[@@deriving yojson]

type execution_request = {
  protocol_version : Tool_protocol.version;
  filename : string;
  whyml_text : string;
  options : execution_options;
}
[@@deriving yojson]

type goal_descriptor = { goal_index : int; goal_name : string } [@@deriving yojson]

type goal_result = {
  goal_index : int;
  goal_name : string;
  status : proof_status;
  prover_time_s : float;
  timing : goal_timing;
  dump_path : string option;
  probe : solver_probe option;
}
[@@deriving yojson]

type worker_metrics = {
  worker_id : int;
  input_goal_count : int;
  prover_goal_count : int;
  duplicate_goal_count : int;
  fallback_count : int;
  wall_s : float;
  prepare_s : float;
  print_s : float;
  spawn_s : float;
  wait_s : float;
  solver_s : float;
  last_goal : string;
}
[@@deriving yojson]

type execution_metrics = {
  setup_s : float;
  parse_s : float;
  typecheck_s : float;
  task_extract_s : float;
  split_vc_s : float;
  prepare_s : float;
  print_s : float;
  spawn_s : float;
  wait_s : float;
  solver_s : float;
  input_goal_count : int;
  prover_goal_count : int;
  duplicate_goal_count : int;
  fallback_count : int;
  smt_fingerprint_count : int;
  unique_smt_fingerprint_count : int;
  workers : worker_metrics list;
}
[@@deriving yojson]

type execution_response = {
  protocol_version : Tool_protocol.version;
  goals : goal_descriptor list;
  results : goal_result list;
  vc_blocks : string list;
  smt_blocks : string list;
  metrics : execution_metrics;
}
[@@deriving yojson]

val make_execution_request :
  ?filename:string -> whyml_text:string -> options:execution_options -> unit -> execution_request

val validate_execution_request : execution_request -> (unit, string) result

val make_execution_response :
  goals:goal_descriptor list ->
  results:goal_result list ->
  vc_blocks:string list ->
  smt_blocks:string list ->
  metrics:execution_metrics ->
  execution_response

val validate_execution_response : execution_response -> (unit, string) result
val string_of_proof_status : proof_status -> string
val proof_status_is_valid : proof_status -> bool
