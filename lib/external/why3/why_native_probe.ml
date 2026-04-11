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

type native_unsat_core = {
  solver : string;
  hypothesis_ids : int list;
  smt_text : string;
}

type native_solver_probe = {
  solver : string;
  status : string;
  detail : string option;
  model_text : string option;
  smt_text : string;
}

(* Render one Why3 task to SMT-LIB text with the selected driver. *)
let task_to_smt2_with_driver ~(driver : Driver.driver) (task : Task.task) : string =
  let prepared = Driver.prepare_task driver task in
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  ignore (Driver.print_task_prepared driver fmt prepared);
  Format.pp_print_flush fmt ();
  Buffer.contents buffer

let status_and_detail_of_answer (answer : Call_provers.prover_answer) :
    string * string option =
  match answer with
  | Call_provers.Valid -> ("valid", None)
  | Call_provers.Invalid -> ("invalid", Some "The prover reported a concrete invalid goal.")
  | Call_provers.Timeout -> ("timeout", None)
  | Call_provers.StepLimitExceeded -> ("timeout", Some "Step limit exceeded.")
  | Call_provers.Unknown msg -> ("unknown", Some msg)
  | Call_provers.OutOfMemory -> ("oom", Some "Out of memory.")
  | Call_provers.Failure msg -> ("failure", Some msg)
  | Call_provers.HighFailure msg -> ("failure", Some msg)

(* Unsat-core diagnostic path.
   With API-only proving we do not have a portable unsat-core extraction path. *)
let native_unsat_core_for_goal_of_ptree ?(timeout = 5) ~(ptree : Ptree.mlw_file)
    ~(goal_index : int) () : native_unsat_core option =
  let _ = timeout in
  let _ = ptree in
  let _ = goal_index in
  None

(* Native replay diagnostic path for one normalized goal (status/detail + dumped
   SMT task text), using Why3's driver/prover API. *)
let native_solver_probe_for_goal_of_ptree ?(timeout = 5) ~(ptree : Ptree.mlw_file)
    ~(goal_index : int) () : native_solver_probe option =
  let config, main, env, datadir_opt = setup_env () in
  let tasks_with_wids = normalize_tasks_with_wids_of_ptree ~env ~ptree in
  match List.nth_opt tasks_with_wids goal_index with
  | None -> None
  | Some (task, _) ->
      let prover_cfg = select_z3_prover_cfg ~config ~datadir_opt in
      let driver = Driver.load_driver_for_prover main env prover_cfg in
      let smt_text = task_to_smt2_with_driver ~driver task in
      let prepared = Driver.prepare_task driver task in
      let buffer = Buffer.create 4096 in
      let fmt = Format.formatter_of_buffer buffer in
      let printing_info = Driver.print_task_prepared driver fmt prepared in
      Format.pp_print_flush fmt ();
      let limits =
        {
          Call_provers.empty_limits with
          limit_time = float_of_int timeout;
          limit_mem = Whyconf.memlimit main;
        }
      in
      let command = Whyconf.get_complete_command prover_cfg ~with_steps:false in
      let goal_name =
        try
          let pr = Task.task_goal prepared in
          pr.Decl.pr_name.Ident.id_string
        with _ -> "goal"
      in
      let call =
        Driver.prove_buffer_prepared ~command ~config:main ~limits ~theory_name:"generated"
          ~goal_name ~get_model:printing_info driver buffer
      in
      let answer = (Call_provers.wait_on_call call).Call_provers.pr_answer in
      let status, detail = status_and_detail_of_answer answer in
      Some
        {
          solver = prover_cfg.Whyconf.prover.Whyconf.prover_name;
          status;
          detail;
          model_text = None;
          smt_text;
        }
