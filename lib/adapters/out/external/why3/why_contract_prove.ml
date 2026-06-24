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
open Why_contract_unix_io

module Persistent_z3 = Why_contract_persistent_z3

type goal_proof_result = {
  goal_name : string;
  prover_result : Call_provers.prover_result;
  dump_path : string option;
  timing : goal_timing;
}

and goal_timing = {
  prepare_s : float;
  print_s : float;
  spawn_s : float;
  wait_s : float;
  solver_s : float;
}

let zero_goal_timing =
  {
    prepare_s = 0.0;
    print_s = 0.0;
    spawn_s = 0.0;
    wait_s = 0.0;
    solver_s = 0.0;
  }

let add_goal_timing left right =
  {
    prepare_s = left.prepare_s +. right.prepare_s;
    print_s = left.print_s +. right.print_s;
    spawn_s = left.spawn_s +. right.spawn_s;
    wait_s = left.wait_s +. right.wait_s;
    solver_s = left.solver_s +. right.solver_s;
  }

let goal_timing_with_prepare prepare_s =
  { zero_goal_timing with prepare_s }

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

type worker_to_parent =
  | Worker_started of {
      task_index : int;
      goal_name : string;
      fingerprint : string;
    }
  | Worker_result of {
      task_index : int;
      fingerprint : string;
      result : goal_proof_result;
    }
  | Worker_done of
      External_timing.why3_worker_snapshot * External_timing.snapshot
  | Worker_failed of string * External_timing.snapshot

type proof_worker = {
  worker_id : int;
  worker_pid : int;
  worker_input : in_channel;
  worker_fd : Unix.file_descr;
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
    ~(dump_failed_smt : bool)
    ~(task_index : int) 
    ~(prover_result : Call_provers.prover_result)
    ~(buffer : Buffer.t) : string option =
      if (not dump_failed_smt) || prover_result.pr_answer = Call_provers.Valid then None
      else Some (dump_failed_task_buffer ~task_index ~buffer)

let strip_smt_named_attributes (line : string) : string =
  let named = ":named" in
  let named_len = String.length named in
  let line_len = String.length line in
  let is_space = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false in
  let rec starts_with_at i =
    i + named_len <= line_len
    && String.sub line i named_len = named
    && (i = 0 || is_space line.[i - 1] || line.[i - 1] = '(')
    && (i + named_len = line_len
       || is_space line.[i + named_len]
       || line.[i + named_len] = ')')
  in
  let rec skip_spaces i =
    if i < line_len && is_space line.[i] then skip_spaces (i + 1) else i
  in
  let skip_symbol i =
    if i < line_len && line.[i] = '|' then
      let rec skip_bar j =
        if j >= line_len then j
        else if line.[j] = '|' then j + 1
        else skip_bar (j + 1)
      in
      skip_bar (i + 1)
    else
      let rec skip_plain j =
        if j >= line_len || is_space line.[j] || line.[j] = ')' then j
        else skip_plain (j + 1)
      in
      skip_plain i
  in
  let buffer = Buffer.create line_len in
  let rec loop i =
    if i >= line_len then ()
    else if starts_with_at i then (
      Buffer.add_string buffer ":named _";
      loop (skip_symbol (skip_spaces (i + named_len))))
    else (
      Buffer.add_char buffer line.[i];
      loop (i + 1))
  in
  loop 0;
  Buffer.contents buffer

let smt_fingerprint (text : string) : string =
  text |> String.split_on_char '\n'
  |> List.filter (fun line ->
         let trimmed = String.trim line in
         trimmed <> "" && not (String.starts_with ~prefix:";" trimmed))
  |> List.map strip_smt_named_attributes
  |> String.concat "\n"

let duplicate_detail_for_goal ~(goal_name : string)
    (detail : goal_proof_result) : goal_proof_result =
  {
    detail with
    goal_name;
    prover_result = { detail.prover_result with Call_provers.pr_time = 0.0 };
    timing = zero_goal_timing;
  }

let prepare_task_with_timing ~(driver : Driver.driver) task =
  let t_prepare = Unix.gettimeofday () in
  let prepared = Driver.prepare_task driver task in
  External_timing.record_why3_prepare
    ~elapsed_s:(Unix.gettimeofday () -. t_prepare);
  prepared

let print_prepared_task ~(handle : prover_handle) ~(prepared : Task.task) =
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  let t_print = Unix.gettimeofday () in
  let printing_info = Driver.print_task_prepared handle.driver fmt prepared in
  Format.pp_print_flush fmt ();
  let print_s = Unix.gettimeofday () -. t_print in
  External_timing.record_why3_print ~elapsed_s:print_s;
  let fingerprint = smt_fingerprint (Buffer.contents buffer) in
  External_timing.record_why3_smt_fingerprint fingerprint;
  (buffer, fingerprint, printing_info, print_s)

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
  let spawn_s = Unix.gettimeofday () -. t_spawn in
  External_timing.record_why3_spawn ~elapsed_s:spawn_s;
  (call, spawn_s)

let start_prover_call
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(handle : prover_handle)
    ~(prepared : Task.task)
    ~(goal_name : string) =
  let buffer, fingerprint, printing_info, print_s =
    print_prepared_task ~handle ~prepared
  in
  let call, spawn_s =
    spawn_prover_call ~why3_main ~limits ~handle ~goal_name ~buffer
      ~printing_info
  in
  (call, buffer, fingerprint, { zero_goal_timing with print_s; spawn_s })

let wait_on_prover_call call =
  let t_wait = Unix.gettimeofday () in
  let result = Call_provers.wait_on_call call in
  let wait_s = Unix.gettimeofday () -. t_wait in
  External_timing.record_why3_wait ~elapsed_s:wait_s
    ~solver_s:result.Call_provers.pr_time;
  ( result,
    {
      zero_goal_timing with
      wait_s;
      solver_s = result.Call_provers.pr_time;
    } )

let run_prepared_task
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(handle : prover_handle)
  ~(prepared : Task.task)
  ~(goal_name : string) =
  let call, buffer, _fingerprint, timing =
    start_prover_call ~why3_main ~limits ~handle ~prepared ~goal_name
  in
  let result, wait_timing = wait_on_prover_call call in
  (result, buffer, add_goal_timing timing wait_timing)

let result_after_optional_fallback
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary_result : Call_provers.prover_result)
    ~(primary_buffer : Buffer.t)
    ~(fallback : prover_handle option)
    ~(dump_failed_smt : bool)
    ~(task_index : int)
    ~(prepared : Task.task)
    ~(goal_name : string)
    ~(timing : goal_timing) : goal_proof_result =
  match (primary_result.Call_provers.pr_answer, fallback) with
  | Call_provers.Valid, _ ->
      { goal_name; prover_result = primary_result; dump_path = None; timing }
  | _, Some fallback_handle -> (
      External_timing.record_why3_fallback ();
      let fallback_result, fallback_buffer, fallback_timing =
        run_prepared_task ~why3_main ~limits ~handle:fallback_handle ~prepared
          ~goal_name
      in
      let timing = add_goal_timing timing fallback_timing in
      match fallback_result.Call_provers.pr_answer with
      | Call_provers.Valid ->
          { goal_name; prover_result = fallback_result; dump_path = None; timing }
      | _ ->
          let dump_path =
            dump_path_of_prover_answer ~dump_failed_smt ~task_index
              ~prover_result:primary_result ~buffer:primary_buffer
          in
          let _ = fallback_buffer in
          { goal_name; prover_result = primary_result; dump_path; timing })
  | _, None ->
      let dump_path =
        dump_path_of_prover_answer ~dump_failed_smt ~task_index
          ~prover_result:primary_result ~buffer:primary_buffer
      in
      { goal_name; prover_result = primary_result; dump_path; timing }

(* Prove one prepared normalized task and return its detailed result. *)
let prove_one_task_with_details 
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits) 
    ~(primary : prover_handle)
    ~(fallback : prover_handle option)
  ~(dump_failed_smt : bool)
  ~(task_index : int)
  ~(prepared : Task.task)
  ~(goal_name : string) : goal_proof_result =
  let primary_result, primary_buffer, primary_timing =
    run_prepared_task ~why3_main ~limits ~handle:primary ~prepared ~goal_name
  in
  result_after_optional_fallback ~why3_main ~limits ~primary_result
    ~primary_buffer ~fallback ~dump_failed_smt ~task_index ~prepared ~goal_name
    ~timing:primary_timing

let distribute_indexed_tasks ~jobs indexed_tasks =
  let worker_count = min (max 1 jobs) (List.length indexed_tasks) in
  if worker_count = 0 then []
  else
    let buckets = Array.make worker_count [] in
    List.iteri
      (fun pos task ->
        let worker_id = pos mod worker_count in
        buckets.(worker_id) <- task :: buckets.(worker_id))
      indexed_tasks;
    buckets |> Array.to_list |> List.mapi (fun worker_id tasks ->
        (worker_id, List.rev tasks))

let worker_error_message exn =
  let backtrace = Printexc.get_backtrace () in
  if backtrace = "" then Printexc.to_string exn
  else Printf.sprintf "%s\n%s" (Printexc.to_string exn) backtrace

let prove_printed_prepared_task
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary : prover_handle)
    ~(fallback : prover_handle option)
    ~(persistent_z3 : Persistent_z3.runner option)
    ~(dump_failed_smt : bool)
    ~(task_index : int)
    ~(prepared : Task.task)
    ~(goal_name : string)
    ~(base_timing : goal_timing)
    ~(primary_buffer : Buffer.t)
    ~(printing_info : 'a) : goal_proof_result =
  let primary_result, primary_timing =
    match persistent_z3 with
    | Some runner ->
        let t_wait = Unix.gettimeofday () in
        let result = Persistent_z3.prove_buffer ~runner ~buffer:primary_buffer in
        let wait_s = Unix.gettimeofday () -. t_wait in
        if
          match result.Call_provers.pr_answer with
          | Call_provers.Failure _ | Call_provers.HighFailure _ -> true
          | _ -> false
        then
          let call, spawn_s =
            spawn_prover_call ~why3_main ~limits ~handle:primary ~goal_name
              ~buffer:primary_buffer ~printing_info
          in
          let primary_result, wait_timing = wait_on_prover_call call in
          ( primary_result,
            add_goal_timing { zero_goal_timing with spawn_s } wait_timing )
        else begin
          External_timing.record_why3_wait ~elapsed_s:wait_s
            ~solver_s:result.Call_provers.pr_time;
          ( result,
            {
              zero_goal_timing with
              wait_s;
              solver_s = result.Call_provers.pr_time;
            } )
        end
    | None ->
        let call, spawn_s =
          spawn_prover_call ~why3_main ~limits ~handle:primary ~goal_name
            ~buffer:primary_buffer ~printing_info
        in
        let primary_result, wait_timing = wait_on_prover_call call in
        ( primary_result,
          add_goal_timing { zero_goal_timing with spawn_s } wait_timing )
  in
  let primary_timing =
    add_goal_timing base_timing primary_timing
  in
  result_after_optional_fallback ~why3_main ~limits ~primary_result
    ~primary_buffer ~fallback ~dump_failed_smt ~task_index ~prepared ~goal_name
    ~timing:primary_timing

let prove_worker_tasks
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary : prover_handle)
    ~(fallback : prover_handle option)
    ~(dump_failed_smt : bool)
    ~(worker_id : int)
    ~(output_fd : Unix.file_descr)
    (tasks : (int * Task.task) list) =
  External_timing.reset ();
  Prove_client.set_max_running_provers 1;
  let worker_start_s = Unix.gettimeofday () in
  let last_goal = ref "" in
  let persistent_z3 =
    Some
      (Persistent_z3.create
         ~timeout_s:(max 1.0 limits.Call_provers.limit_time)
         ~command:primary.command)
  in
  let close_persistent_z3 () =
    Option.iter Persistent_z3.close persistent_z3
  in
  try
    let proved_by_fingerprint = Hashtbl.create (List.length tasks * 2 + 1) in
    List.iter
      (fun (task_index, task) ->
        let t_prepare = Unix.gettimeofday () in
        let prepared = prepare_task_with_timing ~driver:primary.driver task in
        let prepare_s = Unix.gettimeofday () -. t_prepare in
        let goal_name = goal_name_of_prepared_task prepared in
        last_goal := goal_name;
        let primary_buffer, fingerprint, printing_info, print_s =
          print_prepared_task ~handle:primary ~prepared
        in
        send_marshaled_value_fd output_fd
          (Worker_started { task_index; goal_name; fingerprint });
        let result =
          match Hashtbl.find_opt proved_by_fingerprint fingerprint with
          | Some representative ->
              External_timing.record_why3_duplicate_goal ();
              duplicate_detail_for_goal ~goal_name representative
          | None ->
              let result =
                prove_printed_prepared_task ~why3_main ~limits ~primary
                  ~fallback ~persistent_z3 ~dump_failed_smt ~task_index
                  ~prepared ~goal_name
                  ~base_timing:{ zero_goal_timing with prepare_s; print_s }
                  ~primary_buffer ~printing_info
              in
              Hashtbl.replace proved_by_fingerprint fingerprint result;
              result
        in
        send_marshaled_value_fd output_fd
          (Worker_result { task_index; fingerprint; result }))
      tasks;
    let timing = External_timing.snapshot () in
    let worker_summary : External_timing.why3_worker_snapshot =
      {
        worker_id;
        worker_input_goal_count = List.length tasks;
        worker_prover_goal_count = timing.why3_goal_count;
        worker_duplicate_goal_count = timing.why3_duplicate_goal_count;
        worker_fallback_count = timing.why3_fallback_count;
        worker_wall_s = Unix.gettimeofday () -. worker_start_s;
        worker_prepare_s = timing.why3_prepare_s;
        worker_print_s = timing.why3_print_s;
        worker_spawn_s = timing.why3_spawn_s;
        worker_wait_s = timing.why3_wait_s;
        worker_solver_s = timing.why3_solver_s;
        worker_last_goal = !last_goal;
      }
    in
    close_persistent_z3 ();
    send_marshaled_value_fd output_fd (Worker_done (worker_summary, timing))
  with exn ->
    close_persistent_z3 ();
    send_marshaled_value_fd output_fd
      (Worker_failed (worker_error_message exn, External_timing.snapshot ()))

let spawn_proof_worker
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary : prover_handle)
    ~(fallback : prover_handle option)
    ~(dump_failed_smt : bool)
    ~(inherited_workers : proof_worker list)
    ~(worker_id : int)
    ~(tasks : (int * Task.task) list) : proof_worker =
  let parent_read_fd, child_write_fd = Unix.pipe () in
  List.iter set_close_on_exec_noerr [ parent_read_fd; child_write_fd ];
  match Unix.fork () with
  | 0 ->
      List.iter (fun worker -> close_fd_noerr worker.worker_fd) inherited_workers;
      Unix.close parent_read_fd;
      prove_worker_tasks ~why3_main ~limits ~primary ~fallback ~worker_id
        ~dump_failed_smt ~output_fd:child_write_fd tasks;
      close_fd_noerr child_write_fd;
      Unix._exit 0
  | worker_pid ->
      Unix.close child_write_fd;
      let worker_input = Unix.in_channel_of_descr parent_read_fd in
      let worker_fd = Unix.descr_of_in_channel worker_input in
      {
        worker_id;
        worker_pid;
        worker_input;
        worker_fd;
      }

let close_proof_worker_channels worker = close_in_noerr worker.worker_input

let read_proof_worker_message worker =
  try Some (Marshal.from_channel worker.worker_input : worker_to_parent)
  with End_of_file -> None

let stop_proof_worker worker =
  close_proof_worker_channels worker

let wait_for_proof_worker (worker : proof_worker) =
  match Unix.waitpid [] worker.worker_pid with
  | _, Unix.WEXITED 0 -> ()
  | _, Unix.WEXITED code ->
      failwith
        (Printf.sprintf "Why3 worker %d exited with code %d" worker.worker_id
           code)
  | _, Unix.WSIGNALED signal ->
      failwith
        (Printf.sprintf "Why3 worker %d killed by signal %d" worker.worker_id
           signal)
  | _, Unix.WSTOPPED signal ->
      failwith
        (Printf.sprintf "Why3 worker %d stopped by signal %d" worker.worker_id
           signal)

let finish_proof_worker worker =
  close_proof_worker_channels worker;
  wait_for_proof_worker worker

let rec wait_for_all_proof_workers = function
  | [] -> ()
  | worker :: rest ->
      (try stop_proof_worker worker with _ -> ());
      (try wait_for_proof_worker worker with _ -> ());
      wait_for_all_proof_workers rest

let proof_worker_for_fd workers fd =
  List.find_opt (fun worker -> worker.worker_fd = fd) workers

let select_ready_proof_worker workers =
  match workers with
  | [] -> None
  | _ -> (
      let fds = List.map (fun worker -> worker.worker_fd) workers in
      match Unix.select fds [] [] (-1.0) with
      | ready_fd :: _, _, _ -> proof_worker_for_fd workers ready_fd
      | _ -> None)

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

let prove_tasks_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(dump_failed_smt = false)
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
      ~dump_failed_smt ~should_cancel ~on_goal_start ~on_goal_done tasks

let prove_ptrees_with_events
  ?(timeout = 30)
  ?(jobs = 1)
  ?(split_vc = true)
  ?(dump_failed_smt = false)
  ?(should_cancel = fun () -> false)
  ?(on_goal_start = fun (_ : goal_start_event) -> ())
  ?(on_goal_done = fun (_ : goal_done_event) -> ())
  (ptrees : Ptree.mlw_file list) : goal_proof_result list =
    let _why3_config, _why3_main, env, _datadir_opt = setup_env () in
    let tasks =
      if split_vc then normalize_tasks_of_ptrees ~env ~ptrees
      else tasks_of_ptrees ~env ~ptrees
    in
    prove_tasks_with_events ~timeout ~jobs ~dump_failed_smt ~should_cancel
      ~on_goal_start ~on_goal_done tasks

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
