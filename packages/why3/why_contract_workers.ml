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
open Why_contract_proof_types
open Why_contract_prover_call
open Why_contract_unix_io

module Persistent_z3 = Why_contract_persistent_z3

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

let prove_worker_tasks
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary : prover_handle)
    ~(fallback : fallback_handle option)
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
    ~(fallback : fallback_handle option)
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
