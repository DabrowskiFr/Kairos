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

let zero_goal_timing : Why_contract_prove.goal_timing =
  {
    prepare_s = 0.0;
    print_s = 0.0;
    spawn_s = 0.0;
    wait_s = 0.0;
    solver_s = 0.0;
  }

let proof_status_is_valid status =
  match String.lowercase_ascii status with
  | "valid" | "proved" -> true
  | _ -> false

let goal_name_of_task task =
  Why_contract_prove.goal_name_of_prepared_task task

let pending ~index ~goal_name ~vcid =
  {
    result_index = index;
    result_goal_name = goal_name;
    result_status = "pending";
    result_time_s = 0.0;
    result_timing = zero_goal_timing;
    result_dump_path = None;
    result_vcid = vcid;
  }

let of_goal_done_event ~vc_ids_ordered ev =
  let idx = ev.Why_contract_prove.goal_index in
  let r = ev.result in
  let status =
    Proof_status_render.of_prover_answer r.prover_result.pr_answer
  in
  let vcid =
    match List.nth_opt vc_ids_ordered idx with
    | Some id -> Some (string_of_int id)
    | None -> None
  in
  ( idx,
    status,
    vcid,
    {
      result_index = idx;
      result_goal_name = r.goal_name;
      result_status = status;
      result_time_s = r.prover_result.pr_time;
      result_timing = r.timing;
      result_dump_path = r.dump_path;
      result_vcid = vcid;
    } )

let sort_by_index =
  List.sort (fun left right -> Int.compare left.result_index right.result_index)

let of_normalized_tasks ~progress ~(cfg : Pipeline_types.config)
    ~(vc_ids_ordered : int list) ~normalized_tasks : t list =
  if cfg.prove && not cfg.wp_only then
    let finished = ref [] in
    let stop_requested = ref false in
    let should_cancel () = cfg.stop_on_first_nonvalid && !stop_requested in
    let proof_jobs = if cfg.stop_on_first_nonvalid then 1 else cfg.proof_jobs in
    let _ =
      Why_contract_prove.prove_tasks_with_events ~timeout:cfg.timeout_s
        ~jobs:proof_jobs ~dump_failed_smt:cfg.dump_failed_smt ~should_cancel
        ~on_goal_start:(fun _ -> ())
        ~on_goal_done:(fun ev ->
          let _idx, status, vcid, result =
            of_goal_done_event ~vc_ids_ordered ev
          in
          Option.iter
            (fun (progress : progress) ->
              progress.emit
                ( result.result_goal_name,
                  status,
                  result.result_time_s,
                  result.result_dump_path,
                  vcid ))
            progress;
          finished := result :: !finished;
          if cfg.stop_on_first_nonvalid && not (proof_status_is_valid status) then
            stop_requested := true)
        normalized_tasks
    in
    sort_by_index !finished
  else
    List.mapi
      (fun idx task ->
        let vcid = List.nth vc_ids_ordered idx in
        let goal_name =
          try goal_name_of_task task
          with _ -> Printf.sprintf "vc-%03d" (idx + 1)
        in
        pending ~index:idx ~goal_name ~vcid:(Some (string_of_int vcid)))
      normalized_tasks

let of_module_ptrees_fast ~(cfg : Pipeline_types.config) ~module_ptrees :
    t list =
  let finished = ref [] in
  let stop_requested = ref false in
  let should_cancel () = cfg.stop_on_first_nonvalid && !stop_requested in
  let proof_jobs = if cfg.stop_on_first_nonvalid then 1 else cfg.proof_jobs in
  let _ =
    Why_contract_prove.prove_ptrees_with_events ~timeout:cfg.timeout_s
      ~jobs:proof_jobs ~split_vc:true ~dump_failed_smt:cfg.dump_failed_smt
      ~should_cancel ~on_goal_start:(fun _ -> ())
      ~on_goal_done:(fun ev ->
        let idx = ev.Why_contract_prove.goal_index in
        let r = ev.result in
        let status =
          Proof_status_render.of_prover_answer r.prover_result.pr_answer
        in
        finished :=
          {
            result_index = idx;
            result_goal_name = r.goal_name;
            result_status = status;
            result_time_s = r.prover_result.pr_time;
            result_timing = r.timing;
            result_dump_path = r.dump_path;
            result_vcid = Some (string_of_int (idx + 1));
          }
          :: !finished;
        if cfg.stop_on_first_nonvalid && not (proof_status_is_valid status) then
          stop_requested := true)
      module_ptrees
  in
  sort_by_index !finished

let vc_ids_from_result_indices results =
  List.map (fun result -> result.result_index + 1) results

let to_goal_info (result : t) : Pipeline_types.goal_info =
  ( result.result_goal_name,
    result.result_status,
    result.result_time_s,
    result.result_dump_path,
    result.result_vcid )
