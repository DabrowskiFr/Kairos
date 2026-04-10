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

let task_to_why3 (task : Task.task) : string =
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  Pretty.print_task fmt task;
  Format.pp_print_flush fmt ();
  Buffer.contents buffer

let dump_why3_tasks_of_ptree ~(ptree : Ptree.mlw_file) : string list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = normalize_tasks_of_ptree ~env ~ptree in
  List.map task_to_why3 tasks

let dump_why3_tasks_with_attrs_impl (tasks : Task.task list) : string list =
  let attrs_to_string (attrs : Ident.Sattr.t) : string =
    Ident.Sattr.elements attrs |> List.map (fun a -> a.Ident.attr_string) |> String.concat ", "
  in
  let task_to_string task =
    let buffer = Buffer.create 4096 in
    let fmt = Format.formatter_of_buffer buffer in
    Pretty.print_task fmt task;
    Format.pp_print_flush fmt ();
    let prop_lines =
      Task.task_decls task
      |> List.filter_map (fun decl ->
             match decl.Decl.d_node with
             | Decl.Dprop (_kind, pr, t) ->
                 let name = pr.Decl.pr_name.Ident.id_string in
                 let attrs = attrs_to_string t.Term.t_attrs in
                 if attrs = "" then None else Some (Printf.sprintf "(* attrs %s: %s *)" name attrs)
             | _ -> None)
    in
    if prop_lines = [] then Buffer.contents buffer
    else Buffer.contents buffer ^ "\n" ^ String.concat "\n" prop_lines ^ "\n"
  in
  List.map task_to_string tasks

let dump_why3_tasks_with_attrs_of_ptree ~(ptree : Ptree.mlw_file) : string list =
  let _config, _main, env, _datadir_opt = setup_env () in
  dump_why3_tasks_with_attrs_impl (normalize_tasks_of_ptree ~env ~ptree)

let task_to_smt2_with_driver ~(driver : Driver.driver) (task : Task.task) : string =
  let prepared = Driver.prepare_task driver task in
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  ignore (Driver.print_task_prepared driver fmt prepared);
  Format.pp_print_flush fmt ();
  Buffer.contents buffer

let dump_smt2_tasks_of_ptree ~(ptree : Ptree.mlw_file) : string list =
  let config, main, env, datadir_opt = setup_env () in
  let prover_cfg = select_z3_prover_cfg ~config ~datadir_opt in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks_with_wids = normalize_tasks_with_wids_of_ptree ~env ~ptree in
  List.map (fun (task, _wids) -> task_to_smt2_with_driver ~driver task) tasks_with_wids
