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

let ptree_of_text ~(filename : string) ~(text : string) : Ptree.mlw_file =
  let lexbuf = Lexing.from_string text in
  Loc.set_file filename lexbuf;
  Lexer.parse_mlw_file lexbuf

let module_ptrees_of_ptree = function
  | Ptree.Modules modules ->
      List.map (fun (module_id, decls) -> Ptree.Modules [ (module_id, decls) ]) modules
  | Ptree.Decls _ as ptree -> [ ptree ]

(* Type un ptree Why3 et extrait les tâches top-level sans éclatement VC. *)
let tasks_of_ptree ~(env : Env.env) ~(ptree : Ptree.mlw_file) : Task.task list =
  let modules = Typing.type_mlw_file env [] "<generated>" ptree in
  Wstdlib.Mstr.fold
    (fun _ m acc -> List.rev_append (Task.split_theory m.Pmodule.mod_theory None None) acc)
    modules []
  |> List.rev

let tasks_of_ptrees ~(env : Env.env) ~(ptrees : Ptree.mlw_file list) : Task.task list =
  List.concat_map (fun ptree -> tasks_of_ptree ~env ~ptree) ptrees

let tasks_of_theories (theories : Theory.theory Wstdlib.Mstr.t) : Task.task list =
  Wstdlib.Mstr.fold
    (fun _ th acc -> List.rev_append (Task.split_theory th None None) acc)
    theories []
  |> List.rev

let ensure_whyml_format_registered () =
  ignore (Lexer.parse_mlw_file : Lexing.lexbuf -> Ptree.mlw_file);
  ignore (Pmodule.mlw_language : Pmodule.mlw_file Env.language)

let read_theories_of_text ~(env : Env.env) ~(filename : string) ~(text : string) :
    Theory.theory Wstdlib.Mstr.t =
  ensure_whyml_format_registered ();
  let suffix =
    match Filename.extension filename with
    | "" -> ".why"
    | ext -> ext
  in
  let tmp, oc = Filename.open_temp_file "kairos-why3-" suffix in
  Fun.protect
    ~finally:(fun () -> try Sys.remove tmp with Sys_error _ -> ())
    (fun () ->
      output_string oc text;
      close_out oc;
      fst (Env.read_file Env.base_language env tmp))

let tasks_of_text ~(env : Env.env) ~(filename : string) ~(text : string) :
    Task.task list =
  let _ = filename in
  tasks_of_theories (read_theories_of_text ~env ~filename ~text)

(* Type un ptree Why3, extrait les tâches, puis applique le split VC pour obtenir
   une liste stable d'obligations élémentaires. *)
let normalize_tasks_of_ptree ~(env : Env.env) ~(ptree : Ptree.mlw_file) : Task.task list =
  tasks_of_ptree ~env ~ptree
  |> List.concat_map (fun task -> Trans.apply_transform "split_vc" env task)

let normalize_tasks_of_ptrees ~(env : Env.env) ~(ptrees : Ptree.mlw_file list) :
    Task.task list =
  List.concat_map (fun ptree -> normalize_tasks_of_ptree ~env ~ptree) ptrees

let normalize_tasks_of_text ~(env : Env.env) ~(filename : string) ~(text : string) :
    Task.task list =
  tasks_of_text ~env ~filename ~text
  |> List.concat_map (fun task -> Trans.apply_transform "split_vc" env task)

(* Cherche un fichier de configuration Why3 explicite (env), puis sur les
   emplacements utilisateur habituels. *)
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

(* Détecte un datadir Why3 utilisable depuis l'environnement, puis via le switch
   opam courant si disponible. *)
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

(* Initialise le contexte Why3 complet:
   - charge config/main,
   - stabilise datadir/loadpath/libdir,
   - construit l'environnement de typage.
   Le tuple retourné est la base commune des passes proof/dump. *)
let setup_env_uncached () =
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
  let config, has_config_file =
    match find_config_file () with
    | Some path -> (Whyconf.init_config (Some path), true)
    | None -> (Whyconf.init_config None, false)
  in
  let base_main = Whyconf.get_main config in
  let base_loadpath = Whyconf.loadpath base_main in
  let keep_config_main = has_config_file && base_loadpath <> [] in
  let main =
    if keep_config_main then base_main
    else
      match datadir_opt with
      | None -> base_main
      | Some datadir ->
          let stdlib = Filename.concat datadir "stdlib" in
          let prefix = Filename.dirname (Filename.dirname datadir) in
          let libdir = Filename.concat prefix "lib/why3" in
          let main = Whyconf.set_datadir base_main datadir in
          let main = if Sys.file_exists libdir then Whyconf.set_libdir main libdir else main in
          if Sys.file_exists stdlib then
            let current = Whyconf.loadpath main in
            if current = [] then Whyconf.set_loadpath main [ stdlib ]
            else if List.mem stdlib current then main
            else Whyconf.set_loadpath main (current @ [ stdlib ])
          else main
  in
  let main =
    match datadir_opt with
    | None -> main
    | Some datadir ->
        let stdlib = Filename.concat datadir "stdlib" in
        let current = Whyconf.loadpath main in
        let with_datadir = if List.mem datadir current then current else datadir :: current in
        let with_stdlib =
          if Sys.file_exists stdlib && not (List.mem stdlib with_datadir) then with_datadir @ [ stdlib ]
          else with_datadir
        in
        Whyconf.set_loadpath main with_stdlib
  in
  let config = Whyconf.set_main config main in
  Whyconf.load_plugins main;
  let env = Env.create_env (Whyconf.loadpath main) in
  (config, main, env, datadir_opt)

let setup_env_cache = ref None

let setup_env () =
  match !setup_env_cache with
  | Some ctx -> ctx
  | None ->
      let ctx = setup_env_uncached () in
      setup_env_cache := Some ctx;
      ctx

(* Fallback minimal pour Z3 quand la configuration Why3 ne fournit pas
   d'entrée prover résoluble, en s'appuyant sur le datadir détecté. *)
let fallback_z3_prover_cfg (datadir_opt : string option) : Whyconf.config_prover option =
  match datadir_opt with
  | None -> None
  | Some datadir ->
      let drivers_dir = Filename.concat datadir "drivers" in
      let driver_candidates =
        [ "z3_487.drv"; "z3_471.drv"; "z3_440.drv"; "z3_432.drv"; "z3.drv" ]
      in
      let driver_file =
        List.find_map
          (fun driver ->
            let path = Filename.concat drivers_dir driver in
            if Sys.file_exists path then Some path else None)
          driver_candidates
      in
      match driver_file with
      | None -> None
      | Some driver_file ->
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

(* Sélectionne la config Z3 dans Why3; si absente, tente un fallback driver
   local avant d'échouer. *)
let select_z3_prover_cfg ~(config : Whyconf.config) ~(datadir_opt : string option) :
    Whyconf.config_prover =
  let filter =
    Whyconf.parse_filter_prover "z3"
    |> Whyconf.filter_prover_with_shortcut config
  in
  try Whyconf.filter_one_prover config filter
  with Whyconf.ProverNotFound _ as exn -> (
    match fallback_z3_prover_cfg datadir_opt with
    | Some prover_cfg -> prover_cfg
    | None -> raise exn)

let select_alt_ergo_prover_cfg ~(config : Whyconf.config) : Whyconf.config_prover option =
  let filter =
    Whyconf.parse_filter_prover "alt-ergo"
    |> Whyconf.filter_prover_with_shortcut config
  in
  try Some (Whyconf.filter_one_prover config filter) with Whyconf.ProverNotFound _ -> None
