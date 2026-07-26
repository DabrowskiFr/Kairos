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

type execution_response = {
  protocol_version : Tool_protocol.version;
  goals : goal_descriptor list;
  results : goal_result list;
  vc_blocks : string list;
  smt_blocks : string list;
}
[@@deriving yojson]

let make_execution_request ?(filename = "<kairos-generated>") ~whyml_text ~options () =
  { protocol_version = Tool_protocol.current_version; filename; whyml_text; options }

let validate_execution_request (request : execution_request) =
  match Tool_protocol.validate ~component:"proof execution request" request.protocol_version with
  | Error _ as error -> error
  | Ok () ->
      if String.trim request.filename = "" then
        Error "proof execution request has an empty filename"
      else if String.trim request.whyml_text = "" then
        Error "proof execution request has an empty WhyML payload"
      else if request.options.timeout_s <= 0 then
        Error "proof execution request has a non-positive timeout"
      else if request.options.jobs <= 0 then
        Error "proof execution request has a non-positive worker count"
      else Ok ()

let make_execution_response ~goals ~results ~vc_blocks ~smt_blocks =
  { protocol_version = Tool_protocol.current_version; goals; results; vc_blocks; smt_blocks }

let validate_execution_response (response : execution_response) =
  match Tool_protocol.validate ~component:"proof execution response" response.protocol_version with
  | Error _ as error -> error
  | Ok () ->
      let goal_count = List.length response.goals in
      let valid_index index = index >= 0 && index < goal_count in
      if
        not
          (List.for_all
             (fun (goal : goal_descriptor) -> valid_index goal.goal_index)
             response.goals)
      then Error "proof execution response has an invalid goal index"
      else if
        not
          (List.for_all
             (fun (result : goal_result) -> valid_index result.goal_index)
             response.results)
      then Error "proof execution response has an invalid result index"
      else Ok ()

let string_of_proof_status = function
  | Pending -> "pending"
  | Valid -> "valid"
  | Invalid -> "invalid"
  | Timeout -> "timeout"
  | Unknown _ -> "unknown"
  | Out_of_memory -> "oom"
  | Failure _ -> "failure"

let proof_status_is_valid = function Valid -> true | _ -> false
