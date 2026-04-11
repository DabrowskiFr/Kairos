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
open Why_labels
open Why_task_support

type goal_proof_result = {
  goal_name : string;
  answer : Call_provers.prover_answer;
  time_s : float;
  dump_path : string option;
  source : string;
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

let goal_attrs_of_prepared_task (prepared : Task.task) : Ident.Sattr.t =
  (Task.task_goal_fmla prepared).Term.t_attrs

(* Prove normalized tasks one by one, emit progress callbacks, and collect
   per-goal results with optional failing SMT dumps.

   Parameters:
   - [driver]: Why3 driver already loaded for the selected prover.
   - [main]: Why3 main config, used by the prover call API.
   - [limits]: per-goal resource limits (timeout/memory).
   - [command]: full prover command resolved from Why3 config.
   - [goal_labels]: fallback provenance labels indexed by goal name.
   - [should_cancel]: cooperative cancellation predicate.
   - [on_goal_start]: callback emitted before launching one goal.
   - [on_goal_done]: callback emitted when one goal finishes.
   - [tasks_with_wids]: normalized Why3 tasks plus associated source ids.
*)
let prove_tasks_with_details ~(driver : Driver.driver) ~(main : Whyconf.main)
    ~(limits : Call_provers.resource_limits) ~(command : string)
    ~(goal_labels : (string, string) Hashtbl.t) ~(should_cancel : unit -> bool)
    ~(on_goal_start : goal_start_event -> unit) ~(on_goal_done : goal_done_event -> unit)
    (tasks_with_wids : (Task.task * int list) list) :
    goal_proof_result list =
  let indexed_tasks = List.mapi (fun i tw -> (i, tw)) tasks_with_wids in
  let total_tasks = List.length indexed_tasks in
  let rec loop pos details = function
    | [] -> List.rev details
    | _ when should_cancel () -> List.rev details
    | (orig_idx, (task, _seed_wids)) :: rest ->
        log_progress ~pos ~total:total_tasks;
        let prepared = Driver.prepare_task driver task in
        let buffer = Buffer.create 4096 in
        let fmt = Format.formatter_of_buffer buffer in
        let printing_info = Driver.print_task_prepared driver fmt prepared in
        Format.pp_print_flush fmt ();
        let goal = goal_name_of_prepared_task prepared in
        on_goal_start { goal_index = orig_idx; goal_name = goal };
        if should_cancel () then List.rev details
        else
        let t0 = Unix.gettimeofday () in
        let answer =
          let call =
            Driver.prove_buffer_prepared ~command ~config:main ~limits ~theory_name:"generated"
              ~goal_name:goal ~get_model:printing_info driver buffer
          in
          let result = Call_provers.wait_on_call call in
          result.Call_provers.pr_answer
        in
        let elapsed = Unix.gettimeofday () -. t0 in
        let dump_path =
          if answer <> Call_provers.Valid then (
            let tmp = Filename.temp_file (Printf.sprintf "why3_failed_%d_" (orig_idx + 1)) ".smt2" in
            Out_channel.with_open_text tmp (fun oc -> output_string oc (Buffer.contents buffer));
            log_failed_goal ~pos ~total:total_tasks ~answer ~dump_path:tmp;
            Some tmp)
          else None
        in
        let provenance =
          let attrs = goal_attrs_of_prepared_task prepared in
          match label_of_attrs attrs with
          | Some lbl -> lbl
          | None -> ( match Hashtbl.find_opt goal_labels goal with Some lbl -> lbl | None -> "")
        in
        let detail =
          {
            goal_name = goal;
            answer;
            time_s = elapsed;
            dump_path;
            source = provenance;
          }
        in
        on_goal_done { goal_index = orig_idx; result = detail };
        if should_cancel () then List.rev (detail :: details)
        else loop (pos + 1) (detail :: details) rest
  in
  loop 0 [] indexed_tasks

(* Public entry point:
   build normalized tasks from a ptree and run the proof loop. *)
let prove_ptree_with_events ?(timeout = 30) ?(should_cancel = fun () -> false)
    ?(on_goal_start = fun (_ : goal_start_event) -> ())
    ?(on_goal_done = fun (_ : goal_done_event) -> ())
    (ptree : Ptree.mlw_file) :
    goal_proof_result list =
  let extract_goal_labels_from_tasks tasks =
    let tbl = Hashtbl.create 64 in
    let comment_re = Str.regexp "^\\s*\\(\\* \\(.*\\) \\*\\)\\s*$" in
    let goal_re = Str.regexp "^\\s*goal[ \t]+\\([A-Za-z0-9_]+\\)\\b" in
    let extract_label task =
      task
      |> String.split_on_char '\n'
      |> List.find_map (fun line ->
             if Str.string_match comment_re line 0 then Some (Str.matched_group 2 line) else None)
      |> Option.value ~default:""
    in
    List.iter
      (fun task ->
        let label = extract_label task in
        if label <> "" then
          match
            String.split_on_char '\n' task
            |> List.find_map (fun line ->
                   if Str.string_match goal_re line 0 then Some (Str.matched_group 1 line) else None)
          with
          | None -> ()
          | Some goal_name -> Hashtbl.replace tbl goal_name label)
      tasks;
    tbl
  in
  let render_task (task : Task.task) : string = Format.asprintf "%a" Pretty.print_task task in
  let config, main, env, datadir_opt = setup_env () in
  let prover_cfg = select_z3_prover_cfg ~config ~datadir_opt in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks_with_wids = normalize_tasks_with_wids_of_ptree ~env ~ptree in
  let limits =
    {
      Call_provers.empty_limits with
      limit_time = float_of_int timeout;
      limit_mem = Whyconf.memlimit main;
    }
  in
  let command = Whyconf.get_complete_command prover_cfg ~with_steps:false in
  let goal_labels =
    let tasks = List.map (fun (task, _wids) -> render_task task) tasks_with_wids in
    extract_goal_labels_from_tasks tasks
  in
  prove_tasks_with_details ~driver ~main ~limits ~command ~goal_labels ~should_cancel
    ~on_goal_start ~on_goal_done tasks_with_wids
