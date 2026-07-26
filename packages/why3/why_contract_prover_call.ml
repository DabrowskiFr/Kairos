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

module Persistent_z3 = Why_contract_persistent_z3
module Smt_utils = Why_contract_smt_utils

type prover_handle = {
  driver : Driver.driver;
  command : string;
}

type fallback_handle = prover_handle Lazy.t

let goal_name_of_prepared_task (prepared : Task.task) : string =
  let pr = Task.task_goal prepared in
  pr.Decl.pr_name.Ident.id_string

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
  let fingerprint = Smt_utils.smt_fingerprint (Buffer.contents buffer) in
  External_timing.record_why3_smt_fingerprint fingerprint;
  (buffer, fingerprint, printing_info, print_s)

let spawn_prover_call
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(handle : prover_handle)
    ~(goal_name : string)
    ~(buffer : Buffer.t)
    ~(printing_info : Printer.printing_info) =
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
    ~(fallback : fallback_handle option)
    ~(dump_failed_smt : bool)
    ~(task_index : int)
    ~(prepared : Task.task)
    ~(goal_name : string)
    ~(timing : goal_timing) : goal_proof_result =
  match (primary_result.Call_provers.pr_answer, fallback) with
  | Call_provers.Valid, _ ->
      { goal_name; prover_result = primary_result; dump_path = None; timing }
  | _, Some fallback -> (
      External_timing.record_why3_fallback ();
      let fallback_handle = Lazy.force fallback in
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
            Smt_utils.dump_path_of_prover_answer ~dump_failed_smt ~task_index
              ~prover_result:primary_result ~buffer:primary_buffer
          in
          let _ = fallback_buffer in
          { goal_name; prover_result = primary_result; dump_path; timing })
  | _, None ->
      let dump_path =
        Smt_utils.dump_path_of_prover_answer ~dump_failed_smt ~task_index
          ~prover_result:primary_result ~buffer:primary_buffer
      in
      { goal_name; prover_result = primary_result; dump_path; timing }

let prove_one_task_with_details
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary : prover_handle)
    ~(fallback : fallback_handle option)
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

let prove_printed_prepared_task
    ~(why3_main : Whyconf.main)
    ~(limits : Call_provers.resource_limits)
    ~(primary : prover_handle)
    ~(fallback : fallback_handle option)
    ~(persistent_z3 : Persistent_z3.runner option)
    ~(dump_failed_smt : bool)
    ~(task_index : int)
    ~(prepared : Task.task)
    ~(goal_name : string)
    ~(base_timing : goal_timing)
    ~(primary_buffer : Buffer.t)
    ~(printing_info : Printer.printing_info) : goal_proof_result =
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
  let primary_timing = add_goal_timing base_timing primary_timing in
  result_after_optional_fallback ~why3_main ~limits ~primary_result
    ~primary_buffer ~fallback ~dump_failed_smt ~task_index ~prepared ~goal_name
    ~timing:primary_timing
