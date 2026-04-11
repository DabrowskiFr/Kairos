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
  answer : Call_provers.prover_answer;
  time_s : float;
  dump_path : string option;
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
      Log.stage_info (Some Stage_names.Prove)
        (Printf.sprintf "proving goal %d/%d" (pos + 1) total)
        []

let log_failed_goal ~pos ~total ~answer ~dump_path =
  Log.warning ~stage:Stage_names.Prove
    (Printf.sprintf "goal %d/%d failed (%s); dumped to %s" (pos + 1) total
       (answer_status answer)
       dump_path)

let goal_name_of_prepared_task (prepared : Task.task) : string =
  let pr = Task.task_goal prepared in
  pr.Decl.pr_name.Ident.id_string

type prove_task_env = {
  driver : Driver.driver;
  main : Whyconf.main;
  limits : Call_provers.resource_limits;
  command : string;
}

(* Prove one prepared normalized task and return its detailed result. *)
let prove_one_task_with_details ~(env : prove_task_env) ~(task_index : int)
    ~(prepared : Task.task) ~(goal : string) : goal_proof_result =
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  let printing_info = Driver.print_task_prepared env.driver fmt prepared in
  Format.pp_print_flush fmt ();
  let t0 = Unix.gettimeofday () in
  let answer =
    let call =
      Driver.prove_buffer_prepared ~command:env.command ~config:env.main ~limits:env.limits
        ~theory_name:"generated" ~goal_name:goal ~get_model:printing_info env.driver buffer
    in
    let result = Call_provers.wait_on_call call in
    result.Call_provers.pr_answer
  in
  let elapsed = Unix.gettimeofday () -. t0 in
  let dump_path =
    if answer <> Call_provers.Valid then (
      let tmp = Filename.temp_file (Printf.sprintf "why3_failed_%d_" (task_index + 1)) ".smt2" in
      Out_channel.with_open_text tmp (fun oc -> output_string oc (Buffer.contents buffer));
      Some tmp)
    else None
  in
  {
    goal_name = goal;
    answer;
    time_s = elapsed;
    dump_path;
  }

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
let prove_tasks_with_details ~(driver : Driver.driver) ~(main : Whyconf.main)
    ~(limits : Call_provers.resource_limits) ~(command : string)
    ~(should_cancel : unit -> bool)
    ~(on_goal_start : goal_start_event -> unit) ~(on_goal_done : goal_done_event -> unit)
    (tasks : Task.task list) :
    goal_proof_result list =
  let indexed_tasks = List.mapi (fun i task -> (i, task)) tasks in
  let total_tasks = List.length indexed_tasks in
  let env = { driver; main; limits; command } in
  let rec loop pos details = function
    | [] -> List.rev details
    | _ when should_cancel () -> List.rev details
    | (task_index, task) :: rest -> (
        log_progress ~pos ~total:total_tasks;
        let prepared = Driver.prepare_task driver task in
        let goal = goal_name_of_prepared_task prepared in
        on_goal_start { goal_index = task_index; goal_name = goal };
        if should_cancel () then List.rev details
        else
          let detail = prove_one_task_with_details ~env ~task_index ~prepared ~goal in
          on_goal_done { goal_index = task_index; result = detail };
          (match (detail.answer, detail.dump_path) with
          | answer, Some dump_path when answer <> Call_provers.Valid ->
              log_failed_goal ~pos ~total:total_tasks ~answer ~dump_path
          | _ -> ());
          if should_cancel () then List.rev (detail :: details)
          else loop (pos + 1) (detail :: details) rest)
  in
  loop 0 [] indexed_tasks

(* Public entry point:
   build normalized tasks from a ptree and run the proof loop. *)
let prove_ptree_with_events ?(timeout = 30) ?(should_cancel = fun () -> false)
    ?(on_goal_start = fun (_ : goal_start_event) -> ())
    ?(on_goal_done = fun (_ : goal_done_event) -> ())
    (ptree : Ptree.mlw_file) :
    goal_proof_result list =
  let config, main, env, datadir_opt = setup_env () in
  let prover_cfg = select_z3_prover_cfg ~config ~datadir_opt in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks = normalize_tasks_of_ptree ~env ~ptree in
  let limits =
    {
      Call_provers.empty_limits with
      limit_time = float_of_int timeout;
      limit_mem = Whyconf.memlimit main;
    }
  in
  let command = Whyconf.get_complete_command prover_cfg ~with_steps:false in
  prove_tasks_with_details ~driver ~main ~limits ~command ~should_cancel
    ~on_goal_start ~on_goal_done tasks
