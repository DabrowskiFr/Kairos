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

let tasks_of_ptree ~(env : Env.env) ~(ptree : Ptree.mlw_file) : Task.task list =
  let mods = Typing.type_mlw_file env [] "<generated>" ptree in
  Wstdlib.Mstr.fold
    (fun _ m acc -> List.rev_append (Task.split_theory m.Pmodule.mod_theory None None) acc)
    mods []
  |> List.rev

let apply_transform name env tasks =
  List.concat_map (fun task -> Trans.apply_transform name env task) tasks

let normalize_tasks_of_ptree ~(env : Env.env) ~(ptree : Ptree.mlw_file) : Task.task list =
  tasks_of_ptree ~env ~ptree |> apply_transform "split_vc" env

let extract_trace_ids_from_attrs (attrs : Ident.Sattr.t) : int list =
  Ident.Sattr.elements attrs
  |> List.filter_map (fun attr ->
         let s = attr.Ident.attr_string in
         let parse_with_prefix prefix =
           let plen = String.length prefix in
           if String.length s >= plen && String.sub s 0 plen = prefix then
             try Some (int_of_string (String.sub s plen (String.length s - plen))) with _ -> None
           else None
         in
         match parse_with_prefix "wid:" with
         | Some _ as id -> id
         | None -> parse_with_prefix "rid:")

let task_wids_deep (task : Task.task) : int list =
  let wids = ref [] in
  let add_wids attrs =
    extract_trace_ids_from_attrs attrs
    |> List.iter (fun w -> if List.mem w !wids then () else wids := w :: !wids)
  in
  let add_wids_from_term (t : Term.term) =
    add_wids t.Term.t_attrs;
    ignore
      (Term.t_fold
         (fun () tm ->
           add_wids tm.Term.t_attrs;
           ())
         () t)
  in
  begin try add_wids_from_term (Task.task_goal_fmla task) with _ -> ()
  end;
  Task.task_decls task
  |> List.iter (fun decl ->
         match decl.Decl.d_node with
         | Decl.Dprop (_kind, _pr, t) -> add_wids_from_term t
         | _ -> ());
  List.rev !wids

let normalize_tasks_with_wids_impl ~(env : Env.env) (tasks0 : Task.task list) :
    (Task.task * int list) list =
  List.concat_map
    (fun task0 ->
      let parent_wids = task_wids_deep task0 in
      let split = Trans.apply_transform "split_vc" env task0 in
      List.map
        (fun t ->
          let local_wids = task_wids_deep t in
          if local_wids = [] then (t, parent_wids) else (t, local_wids))
        split)
    tasks0

let normalize_tasks_with_wids_of_ptree ~(env : Env.env) ~(ptree : Ptree.mlw_file) :
    (Task.task * int list) list =
  normalize_tasks_with_wids_impl ~env (tasks_of_ptree ~env ~ptree)

let find_config_file () =
  let env_opt name =
    match Sys.getenv_opt name with Some path when Sys.file_exists path -> Some path | _ -> None
  in
  match env_opt "WHY3_CONFIG" with
  | Some _ as c -> c
  | None ->
      let home = match Sys.getenv_opt "HOME" with Some h -> h | None -> "" in
      let candidates =
        [ Filename.concat home ".why3.conf"; Filename.concat home ".config/why3/why3.conf" ]
      in
      List.find_map (fun path -> if Sys.file_exists path then Some path else None) candidates

let find_datadir () =
  let env_opt name =
    match Sys.getenv_opt name with Some path when Sys.file_exists path -> Some path | _ -> None
  in
  let candidate path = if Sys.file_exists path then Some path else None in
  match env_opt "WHY3_DATADIR" with
  | Some _ as d -> d
  | None -> begin
      match env_opt "WHY3DATADIR" with
      | Some _ as d -> d
      | None -> begin
          match Sys.getenv_opt "OPAM_SWITCH_PREFIX" with
          | Some prefix -> candidate (Filename.concat prefix "share/why3")
          | None -> None
        end
    end

let load_config () =
  match find_config_file () with
  | Some path -> Whyconf.read_config (Some path)
  | None -> Whyconf.init_config None

let setup_env () =
  let datadir_opt = find_datadir () in
  let () =
    match datadir_opt with
    | None -> ()
    | Some datadir ->
        Unix.putenv "WHY3DATADIR" datadir;
        Unix.putenv "WHY3_DATADIR" datadir;
        let stdlib = Filename.concat datadir "stdlib" in
        if Sys.file_exists stdlib then Whyconf.stdlib_path := stdlib
  in
  let config = load_config () |> Whyconf.set_load_default_plugins false in
  let main =
    match datadir_opt with
    | None -> Whyconf.get_main config
    | Some datadir ->
        let stdlib = Filename.concat datadir "stdlib" in
        let prefix = Filename.dirname (Filename.dirname datadir) in
        let libdir = Filename.concat prefix "lib/why3" in
        let main = Whyconf.get_main config |> fun m -> Whyconf.set_datadir m datadir in
        let main = if Sys.file_exists libdir then Whyconf.set_libdir main libdir else main in
        let main = if Sys.file_exists stdlib then Whyconf.set_loadpath main [ stdlib ] else main in
        main
  in
  let config = Whyconf.set_main config main in
  let env = Env.create_env (Whyconf.loadpath main) in
  (config, main, env, datadir_opt)

let fallback_z3_prover_cfg (datadir_opt : string option) : Whyconf.config_prover option =
  match datadir_opt with
  | None -> None
  | Some datadir ->
      let driver_file = Filename.concat datadir "drivers/z3.drv" in
      if not (Sys.file_exists driver_file) then None
      else
        let z3_ok = Sys.command "z3 -version > /dev/null 2>&1" = 0 in
        if not z3_ok then None
        else
          Some
            {
              Whyconf.prover = { prover_name = "Z3"; prover_version = ""; prover_altern = "" };
              command = "z3 -smt2 -T:%t %f";
              command_steps = None;
              driver = (None, driver_file);
              in_place = false;
              editor = "";
              interactive = false;
              extra_options = [];
              extra_drivers = [];
            }

let select_z3_prover_cfg ~(config : Whyconf.config) ~(datadir_opt : string option) :
    Whyconf.config_prover =
  let filter =
    Whyconf.parse_filter_prover "z3"
    |> Whyconf.filter_prover_with_shortcut config
  in
  try Whyconf.filter_one_prover config filter
  with Whyconf.ProverNotFound _ -> (
    match fallback_z3_prover_cfg datadir_opt with
    | Some prover_cfg -> prover_cfg
    | None ->
        let _ = Sys.command "why3 config detect > /dev/null 2>&1" in
        let cfg = load_config () in
        let filter =
          Whyconf.parse_filter_prover "z3"
          |> Whyconf.filter_prover_with_shortcut cfg
        in
        Whyconf.filter_one_prover cfg filter)
