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

type goal_proof_result = {
  goal_name : string;
  prover_result : Call_provers.prover_result;
  dump_path : string option;
}

type prover_handle = {
  driver : Driver.driver;
  command : string;
}

type goal_start_event = {
  goal_index : int;
  goal_name : string;
}

type goal_done_event = {
  goal_index : int;
  result : goal_proof_result;
}

let answer_status = function
  | Call_provers.Valid -> "valid"
  | Call_provers.Invalid -> "invalid"
  | Call_provers.Timeout | Call_provers.StepLimitExceeded -> "timeout"
  | Call_provers.Unknown _ -> "unknown"
  | Call_provers.OutOfMemory -> "oom"
  | Call_provers.Failure _ | Call_provers.HighFailure _ -> "failure"

let log_progress ~pos ~total =
  let should_log_progress ~pos ~total =
    pos = 0 || pos = total - 1 || (pos + 1) mod 10 = 0
  in if should_log_progress ~pos ~total then
      Log.flow_info (Some "prove")
        (Printf.sprintf "proving goal %d/%d" (pos + 1) total)
        []

let log_failed_goal ~pos ~total ~answer ~dump_path =
  Log.warning ~stage:"prove"
    (Printf.sprintf "goal %d/%d failed (%s); dumped to %s" (pos + 1) total
       (answer_status answer)
       dump_path)

let goal_name_of_prepared_task (prepared : Task.task) : string =
  let pr = Task.task_goal prepared in
  pr.Decl.pr_name.Ident.id_string

let dump_failed_task_buffer ~(task_index : int) ~(buffer : Buffer.t) : string =
  let tmp = Filename.temp_file (Printf.sprintf "why3_failed_%d_" (task_index + 1)) ".smt2" in
  Out_channel.with_open_text tmp (fun oc -> output_string oc (Buffer.contents buffer));
  tmp

let dump_path_of_prover_answer 
    ~(task_index : int) 
    ~(prover_result : Call_provers.prover_result)
    ~(buffer : Buffer.t) : string option =
      if prover_result.pr_answer = Call_provers.Valid then None
      else Some (dump_failed_task_buffer ~task_index ~buffer)

let smt_fingerprint (text : string) : string =
  text |> String.split_on_char '\n'
  |> List.filter (fun line ->
         let trimmed = String.trim line in
         trimmed <> "" && not (String.starts_with ~prefix:";" trimmed))
  |> String.concat "\n"

let duplicate_detail_for_goal ~(goal_name : string)
    (detail : goal_proof_result) : goal_proof_result =
  {
    detail with
    goal_name;
    prover_result = { detail.prover_result with Call_provers.pr_time = 0.0 };
  }

let print_prepared_task ~(handle : prover_handle) ~(prepared : Task.task) =
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  let t_print = Unix.gettimeofday () in
  let printing_info = Driver.print_task_prepared handle.driver fmt prepared in
  Format.pp_print_flush fmt ();
  External_timing.record_why3_print
    ~elapsed_s:(Unix.gettimeofday () -. t_print);
  let fingerprint = smt_fingerprint (Buffer.contents buffer) in
  (buffer, fingerprint, printing_info)

let spawn_prover_call
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(handle : prover_handle)
    ~(goal_name : string)
    ~(buffer : Buffer.t)
    ~(printing_info : 'a) =
  let t_spawn = Unix.gettimeofday () in
  let call =
    Driver.prove_buffer_prepared ~command:handle.command ~config:why3_main
      ~limits ~goal_name ~get_model:printing_info handle.driver buffer
  in
  External_timing.record_why3_spawn
    ~elapsed_s:(Unix.gettimeofday () -. t_spawn);
  call

let start_prover_call
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(handle : prover_handle)
    ~(prepared : Task.task)
    ~(goal_name : string) =
  let buffer, fingerprint, printing_info = print_prepared_task ~handle ~prepared in
  let call =
    spawn_prover_call ~why3_main ~limits ~handle ~goal_name ~buffer
      ~printing_info
  in
  (call, buffer, fingerprint)

let wait_on_prover_call call =
  let t_wait = Unix.gettimeofday () in
  let result = Call_provers.wait_on_call call in
  External_timing.record_why3_wait
    ~elapsed_s:(Unix.gettimeofday () -. t_wait)
    ~solver_s:result.Call_provers.pr_time;
  result

let run_prepared_task
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(handle : prover_handle)
  ~(prepared : Task.task)
  ~(goal_name : string) =
  let call, buffer, _fingerprint =
    start_prover_call ~why3_main ~limits ~handle ~prepared ~goal_name
  in
  (wait_on_prover_call call, buffer)

let result_after_optional_fallback
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary_result : Call_provers.prover_result)
    ~(primary_buffer : Buffer.t)
    ~(fallback : prover_handle option)
    ~(task_index : int)
    ~(prepared : Task.task)
    ~(goal_name : string) : goal_proof_result =
  match (primary_result.Call_provers.pr_answer, fallback) with
  | Call_provers.Valid, _ ->
      { goal_name; prover_result = primary_result; dump_path = None }
  | _, Some fallback_handle -> (
      External_timing.record_why3_fallback ();
      let fallback_result, fallback_buffer =
        run_prepared_task ~why3_main ~limits ~handle:fallback_handle ~prepared
          ~goal_name
      in
      match fallback_result.Call_provers.pr_answer with
      | Call_provers.Valid ->
          { goal_name; prover_result = fallback_result; dump_path = None }
      | _ ->
          let dump_path =
            dump_path_of_prover_answer ~task_index ~prover_result:primary_result
              ~buffer:primary_buffer
          in
          let _ = fallback_buffer in
          { goal_name; prover_result = primary_result; dump_path })
  | _, None ->
      let dump_path =
        dump_path_of_prover_answer ~task_index ~prover_result:primary_result
          ~buffer:primary_buffer
      in
      { goal_name; prover_result = primary_result; dump_path }

(* Prove one prepared normalized task and return its detailed result. *)
let prove_one_task_with_details 
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits) 
    ~(primary : prover_handle)
    ~(fallback : prover_handle option)
    ~(task_index : int)
    ~(prepared : Task.task) 
    ~(goal_name : string) : goal_proof_result =
  let primary_result, primary_buffer =
    run_prepared_task ~why3_main ~limits ~handle:primary ~prepared ~goal_name
  in
  result_after_optional_fallback ~why3_main ~limits ~primary_result
    ~primary_buffer ~fallback ~task_index ~prepared ~goal_name

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
    ~(fallback : prover_handle option)
    ~(jobs : int)
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
    let t_prepare = Unix.gettimeofday () in
    let prepared = Driver.prepare_task primary.driver task in
    External_timing.record_why3_prepare
      ~elapsed_s:(Unix.gettimeofday () -. t_prepare);
    prepared
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
  let rec loop_sequential pos details = function
    | [] -> List.rev details
    | _ when should_cancel () -> List.rev details
    | (task_index, task) :: rest -> (
        log_progress ~pos ~total:total_tasks;
        let prepared = prepare_task task in
        let goal_name = goal_name_of_prepared_task prepared in
        on_goal_start { goal_index = task_index; goal_name = goal_name };
        if should_cancel () then List.rev details
        else
          let primary_buffer, fingerprint, printing_info =
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
              let call =
                spawn_prover_call ~why3_main ~limits ~handle:primary ~goal_name
                  ~buffer:primary_buffer ~printing_info
              in
              let primary_result = wait_on_prover_call call in
              let detail =
                result_after_optional_fallback ~why3_main ~limits ~primary_result
                  ~primary_buffer ~fallback ~task_index ~prepared ~goal_name
              in
              Hashtbl.replace proved_by_fingerprint fingerprint detail;
          let detail =
                finish_detail ~log_failure:true ~pos ~task_index ~detail
              in
              if should_cancel () then List.rev (detail :: details)
              else loop_sequential (pos + 1) (detail :: details) rest)
  in
  if jobs = 1 then loop_sequential 0 [] indexed_tasks
  else
    let inflight_waiters_by_fingerprint =
      Hashtbl.create (min total_tasks (jobs * 4 + 1))
    in
    let start_one pos (task_index, task) =
      log_progress ~pos ~total:total_tasks;
      let prepared = prepare_task task in
      let goal_name = goal_name_of_prepared_task prepared in
      on_goal_start { goal_index = task_index; goal_name };
      if should_cancel () then None
      else
        let primary_buffer, fingerprint, printing_info =
          print_prepared_task ~handle:primary ~prepared
        in
        match Hashtbl.find_opt proved_by_fingerprint fingerprint with
        | Some representative ->
            Some
              (`Finished
                (pos, task_index, goal_name, representative))
        | None -> (
            match Hashtbl.find_opt inflight_waiters_by_fingerprint fingerprint with
            | Some waiters ->
                waiters := (pos, task_index, goal_name) :: !waiters;
                Some `Waiting
            | None ->
                let waiters = ref [] in
                Hashtbl.add inflight_waiters_by_fingerprint fingerprint waiters;
                let call =
                  spawn_prover_call ~why3_main ~limits ~handle:primary ~goal_name
                    ~buffer:primary_buffer ~printing_info
                in
                Some
                  (`Running
                    ( pos,
                      task_index,
                      prepared,
                      goal_name,
                      call,
                      primary_buffer,
                      fingerprint,
                      waiters )))
    in
    let rec fill_window pos inflight rest details =
      if List.length inflight >= jobs || should_cancel () then
        (pos, inflight, rest, details)
      else
        match rest with
        | [] -> (pos, inflight, rest, details)
        | task :: rest' -> (
            match start_one pos task with
            | None -> (pos + 1, inflight, rest', details)
            | Some (`Finished (dup_pos, dup_task_index, dup_goal_name, representative)) ->
                let details =
                  finish_duplicate_detail ~pos:dup_pos ~task_index:dup_task_index
                    ~goal_name:dup_goal_name ~representative details
                in
                fill_window (pos + 1) inflight rest' details
            | Some `Waiting -> fill_window (pos + 1) inflight rest' details
            | Some (`Running running) ->
                fill_window (pos + 1) (inflight @ [ running ]) rest' details)
    in
    let rec drain pos inflight rest details =
      match inflight with
      | [] -> List.rev details
      | ( run_pos,
          task_index,
          prepared,
          goal_name,
          call,
          primary_buffer,
          fingerprint,
          waiters )
        :: inflight_tail ->
          let primary_result = wait_on_prover_call call in
          let detail =
            result_after_optional_fallback ~why3_main ~limits ~primary_result
              ~primary_buffer ~fallback ~task_index ~prepared ~goal_name
          in
          Hashtbl.replace proved_by_fingerprint fingerprint detail;
          Hashtbl.remove inflight_waiters_by_fingerprint fingerprint;
          let detail =
            finish_detail ~log_failure:true ~pos:run_pos ~task_index ~detail
          in
          let details =
            List.fold_left
              (fun details (dup_pos, dup_task_index, dup_goal_name) ->
                finish_duplicate_detail ~pos:dup_pos ~task_index:dup_task_index
                  ~goal_name:dup_goal_name ~representative:detail details)
              (detail :: details) (List.rev !waiters)
          in
          let pos, inflight, rest, details =
            fill_window pos inflight_tail rest details
          in
          drain pos inflight rest details
    in
    let pos, inflight, rest, details = fill_window 0 [] indexed_tasks [] in
    drain pos inflight rest details

let prove_tasks_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(should_cancel = fun () -> false)
  ?(on_goal_start = fun (_ : goal_start_event) -> ())
  ?(on_goal_done = fun (_ : goal_done_event) -> ())
  (tasks : Task.task list) : goal_proof_result list =
    let why3_config, why3_main, env, datadir_opt = setup_env () in
    Prove_client.set_max_running_provers (max 1 jobs);
    let prover_cfg = select_z3_prover_cfg ~config:why3_config ~datadir_opt in
    let driver = Driver.load_driver_for_prover why3_main env prover_cfg in
    let fallback =
      select_alt_ergo_prover_cfg ~config:why3_config
      |> Option.map (fun cfg ->
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
      ~should_cancel ~on_goal_start ~on_goal_done tasks

let prove_ptrees_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(split_vc = true)
  ?(should_cancel = fun () -> false)
  ?(on_goal_start = fun (_ : goal_start_event) -> ())
  ?(on_goal_done = fun (_ : goal_done_event) -> ())
  (ptrees : Ptree.mlw_file list) : goal_proof_result list =
    let _why3_config, _why3_main, env, _datadir_opt = setup_env () in
    let tasks =
      if split_vc then normalize_tasks_of_ptrees ~env ~ptrees
      else tasks_of_ptrees ~env ~ptrees
    in
    prove_tasks_with_events ~timeout ~jobs ~should_cancel ~on_goal_start
      ~on_goal_done tasks

(* Public entry point:
   build normalized tasks from a ptree and run the proof loop. *)
let prove_ptree_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(split_vc = true)
  ?(should_cancel = fun () -> false)
  ?(on_goal_start = fun (_ : goal_start_event) -> ())
  ?(on_goal_done = fun (_ : goal_done_event) -> ())
  (ptree : Ptree.mlw_file) : goal_proof_result list =
    prove_ptrees_with_events ~timeout ~jobs ~split_vc ~should_cancel ~on_goal_start
      ~on_goal_done [ ptree ]
