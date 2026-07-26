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

open Why3
open Why_task_support

module Persistent_z3 = Why_contract_persistent_z3
module Smt_utils = Why_contract_smt_utils
include Why_contract_proof_types
include Why_contract_prover_call
include Why_contract_workers

let log_progress ~pos ~total =
  let should_log_progress ~pos ~total =
    pos = 0 || pos = total - 1 || (pos + 1) mod 10 = 0
  in
  if should_log_progress ~pos ~total then
    Why_adapter_log.progress
      (Printf.sprintf "proving goal %d/%d" (pos + 1) total)

let log_failed_goal ~pos ~total ~answer ~dump_path =
  Why_adapter_log.warning
    (Printf.sprintf "goal %d/%d failed (%s); dumped to %s" (pos + 1) total
       (Smt_utils.answer_status answer)
       dump_path)

(* Prove normalized tasks one by one, emit progress callbacks, and collect
   per-goal results with optional failing SMT dumps.

   Parameters:
   - [driver]: Why3 driver already loaded for the selected prover.
   - [main]: Why3 main config, used by the prover call API.
   - [limits]: per-goal resource limits (timeout/memory).
   - [command]: full prover command resolved from Why3 config.
   - [should_cancel]: cooperative cancellation predicate.
   - [on_goal_start]: callback emitted before launching one goal.
   - [on_goal_done]: callback emitted when one goal finishes.
   - [tasks]: normalized Why3 tasks.
*)
let prove_tasks_with_details
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits) 
    ~(primary : prover_handle)
    ~(fallback : fallback_handle option)
    ~(jobs : int)
    ~(dump_failed_smt : bool)
    ~(should_cancel : unit -> bool)
    ~(on_goal_start : goal_start_event -> unit) 
    ~(on_goal_done : goal_done_event -> unit)
  (tasks : Task.task list) :
    goal_proof_result list =
  let indexed_tasks = List.mapi (fun i task -> (i, task)) tasks in
  let total_tasks = List.length indexed_tasks in
  External_timing.record_why3_input_goals ~count:total_tasks;
  let jobs = max 1 jobs in
  let proved_by_fingerprint = Hashtbl.create (total_tasks * 2 + 1) in
  let prepare_task task =
    prepare_task_with_timing ~driver:primary.driver task
  in
  let finish_detail ~log_failure ~pos ~task_index ~detail =
    on_goal_done { goal_index = task_index; result = detail };
    (if log_failure then
      match (detail.prover_result.pr_answer, detail.dump_path) with
      | answer, Some dump_path when answer <> Call_provers.Valid ->
          log_failed_goal ~pos ~total:total_tasks ~answer ~dump_path
      | _ -> ());
    detail
  in
  let finish_duplicate_detail ~pos ~task_index ~goal_name ~representative
      details =
    External_timing.record_why3_duplicate_goal ();
    let detail = duplicate_detail_for_goal ~goal_name representative in
    let detail = finish_detail ~log_failure:false ~pos ~task_index ~detail in
    detail :: details
  in
  let sequential_last_goal = ref "" in
  let sequential_persistent_z3 = ref None in
  let open_sequential_persistent_z3 () =
    match !sequential_persistent_z3 with
    | Some runner -> Some runner
    | None ->
        let runner =
          Persistent_z3.create
            ~timeout_s:(max 1.0 limits.Call_provers.limit_time)
            ~command:primary.command
        in
        sequential_persistent_z3 := Some runner;
        Some runner
  in
  let close_sequential_persistent_z3 () =
    match !sequential_persistent_z3 with
    | None -> ()
    | Some runner ->
        sequential_persistent_z3 := None;
        Persistent_z3.close runner
  in
  let rec loop_sequential pos details = function
    | [] -> List.rev details
    | _ when should_cancel () -> List.rev details
    | (task_index, task) :: rest -> (
        log_progress ~pos ~total:total_tasks;
        let t_prepare = Unix.gettimeofday () in
        let prepared = prepare_task task in
        let prepare_s = Unix.gettimeofday () -. t_prepare in
        let goal_name = goal_name_of_prepared_task prepared in
        sequential_last_goal := goal_name;
        on_goal_start { goal_index = task_index; goal_name = goal_name };
        if should_cancel () then List.rev details
        else
          let primary_buffer, fingerprint, printing_info, print_s =
            print_prepared_task ~handle:primary ~prepared
          in
          match Hashtbl.find_opt proved_by_fingerprint fingerprint with
          | Some representative ->
              let details =
                finish_duplicate_detail ~pos ~task_index ~goal_name
                  ~representative details
              in
              if should_cancel () then List.rev details
              else loop_sequential (pos + 1) details rest
          | None ->
              let detail =
                prove_printed_prepared_task ~why3_main ~limits ~primary
                  ~fallback
                  ~persistent_z3:(open_sequential_persistent_z3 ())
                  ~dump_failed_smt ~task_index ~prepared ~goal_name
                  ~base_timing:{ zero_goal_timing with prepare_s; print_s }
                  ~primary_buffer ~printing_info
              in
              Hashtbl.replace proved_by_fingerprint fingerprint detail;
          let detail =
                finish_detail ~log_failure:true ~pos ~task_index ~detail
              in
              if should_cancel () then List.rev (detail :: details)
              else loop_sequential (pos + 1) (detail :: details) rest)
  in
  let loop_workers () =
    if should_cancel () then []
    else
      let batches = distribute_indexed_tasks ~jobs indexed_tasks in
      let started_count = ref 0 in
      let positions_by_task = Hashtbl.create (total_tasks * 2 + 1) in
      let details = ref [] in
      let start_worker_goal ~task_index ~goal_name =
        let pos = !started_count in
        incr started_count;
        Hashtbl.replace positions_by_task task_index pos;
        log_progress ~pos ~total:total_tasks;
        on_goal_start { goal_index = task_index; goal_name }
      in
      let finish_worker_result ~task_index ~(detail : goal_proof_result) =
        let pos =
          Option.value (Hashtbl.find_opt positions_by_task task_index)
            ~default:(max 0 (!started_count - 1))
        in
        let detail = finish_detail ~log_failure:true ~pos ~task_index ~detail in
        details := (task_index, detail) :: !details
      in
      let workers =
        let rec spawn_all spawned = function
          | [] -> List.rev spawned
          | (worker_id, tasks) :: rest ->
              let worker =
                spawn_proof_worker ~why3_main ~limits ~primary ~fallback
                  ~dump_failed_smt ~inherited_workers:spawned ~worker_id ~tasks
              in
              spawn_all (worker :: spawned) rest
        in
        spawn_all [] batches
      in
      let rec loop_active active_workers =
        if active_workers = [] then ()
        else if should_cancel () then (
          wait_for_all_proof_workers active_workers;
          ())
        else
          match select_ready_proof_worker active_workers with
          | None -> loop_active active_workers
          | Some worker -> (
              match read_proof_worker_message worker with
              | None ->
                  wait_for_all_proof_workers active_workers;
                  failwith
                    (Printf.sprintf "Why3 worker %d closed its stream early"
                       worker.worker_id)
              | Some (Worker_started { task_index; goal_name; fingerprint = _ }) ->
                  start_worker_goal ~task_index ~goal_name;
                  loop_active active_workers
              | Some (Worker_result { task_index; fingerprint = _; result }) ->
                  finish_worker_result ~task_index ~detail:result;
                  loop_active active_workers
              | Some (Worker_done (worker_summary, timing)) ->
                  External_timing.add_snapshot timing;
                  External_timing.record_why3_worker worker_summary;
                  finish_proof_worker worker;
                  loop_active
                    (List.filter
                       (fun other -> other.worker_id <> worker.worker_id)
                       active_workers)
              | Some (Worker_failed (message, timing)) ->
                  External_timing.add_snapshot timing;
                  wait_for_all_proof_workers active_workers;
                  failwith
                    (Printf.sprintf "Why3 worker %d failed: %s"
                       worker.worker_id message))
      in
      loop_active workers;
      !details
      |> List.sort (fun (left, _) (right, _) -> Int.compare left right)
      |> List.map snd
  in
  if jobs = 1 then (
    let worker_start_s = Unix.gettimeofday () in
    let before = External_timing.snapshot () in
    let results =
      try
        let results = loop_sequential 0 [] indexed_tasks in
        close_sequential_persistent_z3 ();
        results
      with exn ->
        close_sequential_persistent_z3 ();
        raise exn
    in
    let timing =
      External_timing.diff ~before ~after_:(External_timing.snapshot ())
    in
    External_timing.record_why3_worker
      {
        worker_id = 0;
        worker_input_goal_count = total_tasks;
        worker_prover_goal_count = timing.why3_goal_count;
        worker_duplicate_goal_count = timing.why3_duplicate_goal_count;
        worker_fallback_count = timing.why3_fallback_count;
        worker_wall_s = Unix.gettimeofday () -. worker_start_s;
        worker_prepare_s = timing.why3_prepare_s;
        worker_print_s = timing.why3_print_s;
        worker_spawn_s = timing.why3_spawn_s;
        worker_wait_s = timing.why3_wait_s;
        worker_solver_s = timing.why3_solver_s;
        worker_last_goal = !sequential_last_goal;
      };
    results)
  else loop_workers ()

let prove_tasks_with_events_in_env
    ~(why3_config : Whyconf.config)
    ~(why3_main : Whyconf.main)
    ~(env : Env.env)
    ~(datadir_opt : string option)
    ~(timeout : int)
    ~(jobs : int)
    ~(dump_failed_smt : bool)
    ~(should_cancel : unit -> bool)
    ~(on_goal_start : goal_start_event -> unit)
    ~(on_goal_done : goal_done_event -> unit)
    (tasks : Task.task list) : goal_proof_result list =
    Prove_client.set_max_running_provers (max 1 jobs);
    let prover_cfg = select_z3_prover_cfg ~config:why3_config ~datadir_opt in
    let driver = Driver.load_driver_for_prover why3_main env prover_cfg in
    let fallback =
      select_alt_ergo_prover_cfg ~config:why3_config
      |> Option.map (fun cfg ->
             lazy
               {
                 driver = Driver.load_driver_for_prover why3_main env cfg;
                 command = Whyconf.get_complete_command cfg ~with_steps:false;
               })
    in
    let limits =
      {
        Call_provers.empty_limits with
        limit_time = float_of_int timeout;
        limit_mem = Whyconf.memlimit why3_main;
      }
    in
    let primary =
      { driver; command = Whyconf.get_complete_command prover_cfg ~with_steps:false }
    in
    prove_tasks_with_details ~why3_main ~limits ~primary ~fallback ~jobs
      ~dump_failed_smt ~should_cancel ~on_goal_start ~on_goal_done tasks

let prove_tasks_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(dump_failed_smt = false)
  ?(should_cancel = fun () -> false)
  ?(on_goal_start = fun (_ : goal_start_event) -> ())
  ?(on_goal_done = fun (_ : goal_done_event) -> ())
  (tasks : Task.task list) : goal_proof_result list =
    let why3_config, why3_main, env, datadir_opt = setup_env () in
    prove_tasks_with_events_in_env ~why3_config ~why3_main ~env ~datadir_opt
      ~timeout ~jobs ~dump_failed_smt ~should_cancel ~on_goal_start
      ~on_goal_done tasks

let prove_ptrees_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(split_vc = true)
  ?(dump_failed_smt = false)
  ?(should_cancel = fun () -> false)
  ?(on_goal_start = fun (_ : goal_start_event) -> ())
  ?(on_goal_done = fun (_ : goal_done_event) -> ())
  (ptrees : Ptree.mlw_file list) : goal_proof_result list =
    let why3_config, why3_main, env, datadir_opt = setup_env () in
    let tasks =
      if split_vc then normalize_tasks_of_ptrees ~env ~ptrees
      else tasks_of_ptrees ~env ~ptrees
    in
    prove_tasks_with_events_in_env ~why3_config ~why3_main ~env ~datadir_opt
      ~timeout ~jobs ~dump_failed_smt ~should_cancel ~on_goal_start
      ~on_goal_done tasks

(* Public entry point:
   build normalized tasks from a ptree and run the proof loop. *)
let prove_ptree_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(split_vc = true)
  ?(dump_failed_smt = false)
  ?(should_cancel = fun () -> false)
  ?(on_goal_start = fun (_ : goal_start_event) -> ())
  ?(on_goal_done = fun (_ : goal_done_event) -> ())
  (ptree : Ptree.mlw_file) : goal_proof_result list =
    prove_ptrees_with_events ~timeout ~jobs ~split_vc ~dump_failed_smt
      ~should_cancel ~on_goal_start ~on_goal_done [ ptree ]
