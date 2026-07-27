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

module Contract = Kairos_why3_contract.Why3_contract

type progress = { emit : Pipeline_proof_types.goal_info -> unit }

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

let zero_goal_timing : Contract.goal_timing =
  {
    prepare_s = 0.0;
    print_s = 0.0;
    spawn_s = 0.0;
    wait_s = 0.0;
    solver_s = 0.0;
  }

let pending ~index ~goal_name ~vcid =
  {
    result_index = index;
    result_goal_name = goal_name;
    result_status = "pending";
    result_time_s = 0.0;
    result_timing = zero_goal_timing;
    result_dump_path = None;
    result_vcid = vcid;
    result_probe = None;
  }

let vcid_at vc_ids_ordered index =
  match List.nth_opt vc_ids_ordered index with
  | Some vcid -> Some (string_of_int vcid)
  | None -> Some (string_of_int (index + 1))

let of_contract_result ~vc_ids_ordered (result : Contract.goal_result) =
  {
    result_index = result.goal_index;
    result_goal_name = result.goal_name;
    result_status = Contract.string_of_proof_status result.status;
    result_time_s = result.prover_time_s;
    result_timing = result.timing;
    result_dump_path = result.dump_path;
    result_vcid = vcid_at vc_ids_ordered result.goal_index;
    result_probe = result.probe;
  }

let execute ~progress ~(cfg : Pipeline_config.config) ~whyml_text ~split_vc
    ~emit_vc_text ~emit_smt_text ~diagnose_nonvalid =
  let proof_jobs = if cfg.stop_on_first_nonvalid then 1 else cfg.proof_jobs in
  let options : Contract.execution_options =
    {
      timeout_s = cfg.timeout_s;
      jobs = proof_jobs;
      split_vc;
      dump_failed_smt = cfg.dump_failed_smt;
      prove = cfg.prove && not cfg.wp_only;
      emit_vc_text;
      emit_smt_text;
      diagnose_nonvalid;
    }
  in
  let request = Contract.make_execution_request ~whyml_text ~options () in
  let stop_requested = ref false in
  let should_cancel () = cfg.stop_on_first_nonvalid && !stop_requested in
  let on_goal_done (result : Contract.goal_result) =
    let status = Contract.string_of_proof_status result.status in
    let vcid = Some (string_of_int (result.goal_index + 1)) in
    Option.iter
      (fun (progress : progress) ->
        progress.emit
          ( result.goal_name,
            status,
            result.prover_time_s,
            result.dump_path,
            vcid ))
      progress;
    if cfg.stop_on_first_nonvalid && not (Contract.proof_status_is_valid result.status)
    then stop_requested := true
  in
  let response =
    Why_execution.execute ~should_cancel ~on_goal_done request
  in
  Runtime_metrics.record_why3_execution response.metrics;
  response

let results_of_response ~vc_ids_ordered (response : Contract.execution_response)
    =
  List.map (of_contract_result ~vc_ids_ordered) response.results

let vc_ids_from_result_indices results =
  List.map (fun result -> result.result_index + 1) results

let to_goal_info (result : t) : Pipeline_proof_types.goal_info =
  ( result.result_goal_name,
    result.result_status,
    result.result_time_s,
    result.result_dump_path,
    result.result_vcid )
