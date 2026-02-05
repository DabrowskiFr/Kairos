open Why3
open Provenance
open Why_labels

type summary = {
  total : int;
  valid : int;
  invalid : int;
  unknown : int;
  timeout : int;
  failure : int;
}

type result = {
  status : int;
  summary : summary;
}

let empty_summary = {
  total = 0;
  valid = 0;
  invalid = 0;
  unknown = 0;
  timeout = 0;
  failure = 0;
}

let finalize_summary summary =
  let total =
    summary.valid + summary.invalid + summary.unknown + summary.timeout + summary.failure
  in
  { summary with total }

let add_answer summary (answer:Call_provers.prover_answer) =
  match answer with
  | Call_provers.Valid -> { summary with valid = summary.valid + 1 }
  | Call_provers.Invalid -> { summary with invalid = summary.invalid + 1 }
  | Call_provers.Timeout -> { summary with timeout = summary.timeout + 1 }
  | Call_provers.StepLimitExceeded -> { summary with timeout = summary.timeout + 1 }
  | Call_provers.Unknown _ -> { summary with unknown = summary.unknown + 1 }
  | Call_provers.OutOfMemory -> { summary with failure = summary.failure + 1 }
  | Call_provers.Failure _ -> { summary with failure = summary.failure + 1 }
  | Call_provers.HighFailure _ -> { summary with failure = summary.failure + 1 }

let tasks_of_text ~(env:Env.env) ~(filename:string) ~(text:string) =
  let lexbuf = Lexing.from_string text in
  Loc.set_file filename lexbuf;
  let parsed = Lexer.parse_mlw_file lexbuf in
  let mods = Typing.type_mlw_file env [] filename parsed in
  Wstdlib.Mstr.fold
    (fun _ m acc ->
       List.rev_append (Task.split_theory (Pmodule.mod_theory m) None None) acc)
    mods
    []
  |> List.rev

let apply_transform name env tasks =
  List.concat_map (fun task -> Trans.apply_transform name env task) tasks

let normalize_tasks ~(env:Env.env) ~(text:string) : Task.task list =
  tasks_of_text ~env ~filename:"<generated>" ~text
  |> apply_transform "split_vc" env
  |> apply_transform "simplify_formula" env

let split_vc_tasks ~(env:Env.env) ~(text:string) : Task.task list =
  tasks_of_text ~env ~filename:"<generated>" ~text
  |> apply_transform "split_vc" env

let find_config_file () =
  let env_opt name =
    match Sys.getenv_opt name with
    | Some path when Sys.file_exists path -> Some path
    | _ -> None
  in
  match env_opt "WHY3_CONFIG" with
  | Some _ as c -> c
  | None ->
      let home =
        match Sys.getenv_opt "HOME" with
        | Some h -> h
        | None -> ""
      in
      let candidates = [
        Filename.concat home ".why3.conf";
        Filename.concat home ".config/why3/why3.conf";
      ] in
      List.find_map (fun path -> if Sys.file_exists path then Some path else None) candidates

let find_datadir () =
  let env_opt name =
    match Sys.getenv_opt name with
    | Some path when Sys.file_exists path -> Some path
    | _ -> None
  in
  let candidate path =
    if Sys.file_exists path then Some path else None
  in
  match env_opt "WHY3_DATADIR" with
  | Some _ as d -> d
  | None ->
      begin match env_opt "WHY3DATADIR" with
      | Some _ as d -> d
      | None ->
          begin match Sys.getenv_opt "OPAM_SWITCH_PREFIX" with
          | Some prefix ->
              candidate (Filename.concat prefix "share/why3")
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
        let main =
          if Sys.file_exists libdir then Whyconf.set_libdir main libdir else main
        in
        let main =
          if Sys.file_exists stdlib then Whyconf.set_loadpath main [stdlib] else main
        in
        main
  in
  let config = Whyconf.set_main config main in
  let env = Env.create_env (Whyconf.loadpath main) in
  (config, main, env, datadir_opt)

let rec prove_text ?(timeout=30) ~(prover:string) ~(text:string) () : result =
  let write_text path content =
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in
  let config, main, env, datadir_opt = setup_env () in
  let filter =
    Whyconf.parse_filter_prover prover
    |> Whyconf.filter_prover_with_shortcut config
  in
  let fallback_z3 () =
    let is_z3 =
      String.equal (String.lowercase_ascii prover) "z3"
    in
    if not is_z3 then None
    else
      match datadir_opt with
      | None -> None
      | Some datadir ->
          let driver_file = Filename.concat datadir "drivers/z3.drv" in
          if not (Sys.file_exists driver_file) then None
          else
            let z3_ok =
              Sys.command "z3 -version > /dev/null 2>&1" = 0
            in
            if not z3_ok then None
            else
              Some {
                Whyconf.prover = {
                  prover_name = "Z3";
                  prover_version = "";
                  prover_altern = "";
                };
                command = "z3 -smt2 -T:%t %f";
                command_steps = None;
                driver = (None, driver_file);
                in_place = false;
                editor = "";
                interactive = false;
                extra_options = [];
                extra_drivers = [];
              }
  in
  let ensure_prover cfg =
    try (Whyconf.filter_one_prover cfg filter, false) with
    | Whyconf.ProverNotFound _ ->
        begin match fallback_z3 () with
        | Some prover_cfg -> (prover_cfg, true)
        | None ->
            let _ = Sys.command "why3 config detect > /dev/null 2>&1" in
            let cfg = load_config () in
            (Whyconf.filter_one_prover cfg filter, false)
        end
  in
  let prover_cfg, use_direct_z3 = ensure_prover config in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks =
    tasks_of_text ~env ~filename:"<generated>" ~text
    |> apply_transform "split_vc" env
    |> apply_transform "simplify_formula" env
  in
  let limits = {
    Call_provers.empty_limits with
    limit_time = float_of_int timeout;
    limit_mem = Whyconf.memlimit main;
  } in
  let command = Whyconf.get_complete_command prover_cfg ~with_steps:false in
  let prove_with_z3_direct buffer =
    let tmp = Filename.temp_file "why3_task_" ".smt2" in
    let oc = open_out tmp in
    output_string oc (Buffer.contents buffer);
    close_out oc;
    let cmd =
      Printf.sprintf "z3 -smt2 -T:%d %s" timeout (Filename.quote tmp)
    in
    let ic = Unix.open_process_in cmd in
    let output =
      try input_line ic with End_of_file -> ""
    in
    ignore (Unix.close_process_in ic);
    Sys.remove tmp;
    let out = String.lowercase_ascii output in
    if String.equal out "unsat" then Call_provers.Valid
    else if String.equal out "sat" then Call_provers.Invalid
    else if String.equal out "unknown" then Call_provers.Unknown "unknown"
    else Call_provers.Failure output
  in
  let summary, _details =
    prove_tasks_with_details
      ~write_text
      ~driver
      ~main
      ~limits
      ~command
      ~use_direct_z3
      ~prove_with_z3_direct
      ~goal_labels:(Hashtbl.create 0)
      ~vc_ids_ordered:None
      ~on_goal_start:(fun _ _ -> ())
      ~on_goal_done:(fun _ _ _ _ _ _ _ -> ())
      tasks
  in
  let status =
    if summary.invalid + summary.unknown + summary.timeout + summary.failure = 0
    then 0
    else 1
  in
  { status; summary }

and prove_tasks_with_details
  ~(write_text:string -> string -> unit)
  ~(driver:Driver.driver)
  ~(main:Whyconf.main)
  ~(limits:Call_provers.resource_limits)
  ~(command:string)
  ~(use_direct_z3:bool)
  ~(prove_with_z3_direct:Buffer.t -> Call_provers.prover_answer)
  ~(goal_labels:(string, string) Hashtbl.t)
  ~(vc_ids_ordered:int list option)
  ~(on_goal_start:(int -> string -> unit))
  ~(on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit))
  (tasks:Task.task list)
  : summary * (string * string * float * string option * string * string option) list =
  let total_tasks = List.length tasks in
  let rec loop idx acc details = function
    | [] -> (finalize_summary acc, List.rev details)
    | task :: rest ->
        if idx = 0 || idx = total_tasks - 1 || (idx + 1) mod 10 = 0 then
          Log.stage_info
            (Some Stage_names.Prove)
            (Printf.sprintf "proving goal %d/%d" (idx + 1) total_tasks)
            [];
        let prepared = Driver.prepare_task driver task in
        let buffer = Buffer.create 4096 in
        let fmt = Format.formatter_of_buffer buffer in
        let printing_info = Driver.print_task_prepared driver fmt prepared in
        Format.pp_print_flush fmt ();
        let goal =
          try
            let pr = Task.task_goal prepared in
            pr.Decl.pr_name.Ident.id_string
          with _ -> "goal"
        in
        on_goal_start idx goal;
        let t0 = Unix.gettimeofday () in
        let answer =
          if use_direct_z3 then
            prove_with_z3_direct buffer
          else
            let call =
              Driver.prove_buffer_prepared
                ~command
                ~config:main
                ~limits
                ~theory_name:"generated"
                ~goal_name:goal
                ~get_model:printing_info
                driver
                buffer
            in
            let result = Call_provers.wait_on_call call in
            result.Call_provers.pr_answer
        in
        let elapsed = Unix.gettimeofday () -. t0 in
        let dump_path =
          if answer <> Call_provers.Valid then (
            let tmp =
              Filename.temp_file (Printf.sprintf "why3_failed_%d_" (idx + 1)) ".smt2"
            in
            write_text tmp (Buffer.contents buffer);
            Log.warning
              ~stage:Stage_names.Prove
              (Printf.sprintf "goal %d/%d failed (%s); dumped to %s"
                 (idx + 1) total_tasks
                 (match answer with
                  | Call_provers.Invalid -> "invalid"
                  | Call_provers.Timeout -> "timeout"
                  | Call_provers.StepLimitExceeded -> "timeout"
                  | Call_provers.Unknown _ -> "unknown"
                  | Call_provers.OutOfMemory -> "oom"
                  | Call_provers.Failure _ -> "failure"
                  | Call_provers.HighFailure _ -> "failure"
                  | Call_provers.Valid -> "valid")
                 tmp);
            Some tmp
          ) else None
        in
        let status =
          match answer with
          | Call_provers.Valid -> "valid"
          | Call_provers.Invalid -> "invalid"
          | Call_provers.Timeout -> "timeout"
          | Call_provers.StepLimitExceeded -> "timeout"
          | Call_provers.Unknown _ -> "unknown"
          | Call_provers.OutOfMemory -> "oom"
          | Call_provers.Failure _ -> "failure"
          | Call_provers.HighFailure _ -> "failure"
        in
        let provenance =
          let attrs =
            try (Task.task_goal_fmla prepared).Term.t_attrs with _ -> Ident.Sattr.empty
          in
          match label_of_attrs attrs with
          | Some lbl -> lbl
          | None ->
              match Hashtbl.find_opt goal_labels goal with
              | Some lbl -> lbl
              | None -> ""
        in
        let vcid =
          match vc_ids_ordered with
          | Some ids ->
              begin match List.nth_opt ids idx with
              | Some id -> Some (string_of_int id)
              | None -> None
              end
          | None ->
              let attrs =
                try (Task.task_goal_fmla prepared).Term.t_attrs with _ -> Ident.Sattr.empty
              in
              let why_ids =
                Ident.Sattr.elements attrs
                |> List.filter_map (fun attr ->
                     let s = attr.Ident.attr_string in
                     if String.length s >= 4 && String.sub s 0 4 = "wid:" then
                       try Some (int_of_string (String.sub s 4 (String.length s - 4)))
                       with _ -> None
                     else None)
              in
              if why_ids = [] then None
              else (
                let vc_id = Provenance.fresh_id () in
                Provenance.add_parents ~child:vc_id ~parents:why_ids;
                Some (string_of_int vc_id)
              )
        in
        on_goal_done idx goal status elapsed dump_path provenance vcid;
        loop (idx + 1) (add_answer acc answer) ((goal, status, elapsed, dump_path, provenance, vcid) :: details) rest
  in
  loop 0 empty_summary [] tasks

let dump_why3_tasks ~(text:string) : string list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = normalize_tasks ~env ~text in
  let task_to_string task =
    let buffer = Buffer.create 4096 in
    let fmt = Format.formatter_of_buffer buffer in
    Pretty.print_task fmt task;
    Format.pp_print_flush fmt ();
    Buffer.contents buffer
  in
  List.map task_to_string tasks

let dump_why3_tasks_with_attrs ~(text:string) : string list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = normalize_tasks ~env ~text in
  let attrs_to_string (attrs:Ident.Sattr.t) : string =
    Ident.Sattr.elements attrs
    |> List.map (fun a -> a.Ident.attr_string)
    |> String.concat ", "
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
               if attrs = "" then None
               else Some (Printf.sprintf "(* attrs %s: %s *)" name attrs)
           | _ -> None)
    in
    if prop_lines = [] then Buffer.contents buffer
    else Buffer.contents buffer ^ "\n" ^ String.concat "\n" prop_lines ^ "\n"
  in
  List.map task_to_string tasks

let task_goal_wids ~(text:string) : int list list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = split_vc_tasks ~env ~text in
  let extract_wids attrs =
    Ident.Sattr.elements attrs
    |> List.filter_map (fun attr ->
         let s = attr.Ident.attr_string in
         if String.length s >= 4 && String.sub s 0 4 = "wid:" then
           try Some (int_of_string (String.sub s 4 (String.length s - 4)))
           with _ -> None
         else None)
  in
  let task_wids task =
    let wids = ref [] in
    let add_wids attrs =
      extract_wids attrs
      |> List.iter (fun w -> if List.mem w !wids then () else wids := w :: !wids)
    in
    begin
      try
        add_wids (Task.task_goal_fmla task).Term.t_attrs
      with _ -> ()
    end;
    Task.task_decls task
    |> List.iter (fun decl ->
         match decl.Decl.d_node with
         | Decl.Dprop (_kind, _pr, t) -> add_wids t.Term.t_attrs
         | _ -> ());
    List.rev !wids
  in
  List.map task_wids tasks

let task_sequents ~(text:string) : (string list * string) list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = normalize_tasks ~env ~text in
  let term_to_string t =
    let buf = Buffer.create 256 in
    let fmt = Format.formatter_of_buffer buf in
    Pretty.print_term fmt t;
    Format.pp_print_flush fmt ();
    Buffer.contents buf
  in
  let task_to_sequent task =
    let goal_pr = Task.task_goal task in
    let goal_term = Task.task_goal_fmla task in
    let hyps =
      Task.task_decls task
      |> List.filter_map (fun decl ->
           match decl.Decl.d_node with
           | Decl.Dprop (_kind, pr, t) ->
               if Decl.pr_equal pr goal_pr then None
               else
                 let has_local_news = not (Ident.Sid.is_empty decl.Decl.d_news) in
                 if has_local_news then Some t else None
           | _ -> None)
      |> List.map term_to_string
    in
    (hyps, term_to_string goal_term)
  in
  List.map task_to_sequent tasks

let dump_smt2_tasks ~(prover:string) ~(text:string) : string list =
  let config, main, env, datadir_opt = setup_env () in
  let filter =
    Whyconf.parse_filter_prover prover
    |> Whyconf.filter_prover_with_shortcut config
  in
  let fallback_z3 () =
    let is_z3 =
      String.equal (String.lowercase_ascii prover) "z3"
    in
    if not is_z3 then None
    else
      match datadir_opt with
      | None -> None
      | Some datadir ->
          let driver_file = Filename.concat datadir "drivers/z3.drv" in
          if not (Sys.file_exists driver_file) then None
          else
            let z3_ok =
              Sys.command "z3 -version > /dev/null 2>&1" = 0
            in
            if not z3_ok then None
            else
              Some {
                Whyconf.prover = {
                  prover_name = "Z3";
                  prover_version = "";
                  prover_altern = "";
                };
                command = "z3 -smt2 -T:%t %f";
                command_steps = None;
                driver = (None, driver_file);
                in_place = false;
                editor = "";
                interactive = false;
                extra_options = [];
                extra_drivers = [];
              }
  in
  let prover_cfg =
    try Whyconf.filter_one_prover config filter with
    | Whyconf.ProverNotFound _ ->
        begin match fallback_z3 () with
        | Some prover_cfg -> prover_cfg
        | None ->
            let _ = Sys.command "why3 config detect > /dev/null 2>&1" in
            let cfg = load_config () in
            Whyconf.filter_one_prover cfg filter
        end
  in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks = normalize_tasks ~env ~text in
  let task_to_smt2 task =
    let prepared = Driver.prepare_task driver task in
    let buffer = Buffer.create 4096 in
    let fmt = Format.formatter_of_buffer buffer in
    ignore (Driver.print_task_prepared driver fmt prepared);
    Format.pp_print_flush fmt ();
    Buffer.contents buffer
  in
  List.map task_to_smt2 tasks

let prove_text_detailed_with_callbacks
  ?(timeout=30)
  ~(prover:string)
  ~(text:string)
  ~(vc_ids_ordered:int list option)
  ~(on_goal_start:(int -> string -> unit))
  ~(on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit))
  ()
  : summary * (string * string * float * string option * string * string option) list =
  let extract_goal_labels_from_tasks tasks =
    let tbl = Hashtbl.create 64 in
    let comment_re = Str.regexp "^\\s*\\(\\* \\(.*\\) \\*\\)\\s*$" in
    let goal_re = Str.regexp "^\\s*goal[ \t]+\\([A-Za-z0-9_]+\\)\\b" in
    let extract_label task =
      let labels =
        String.split_on_char '\n' task
        |> List.filter_map (fun line ->
             if Str.string_match comment_re line 0 then
               Some (Str.matched_group 2 line)
             else None)
      in
      match labels with
      | [] -> ""
      | x :: _ -> x
    in
    List.iter
      (fun task ->
        let label = extract_label task in
        if label <> "" then
          match
            let lines = String.split_on_char '\n' task in
            List.find_opt (fun line -> Str.string_match goal_re line 0) lines
          with
          | None -> ()
          | Some line ->
              ignore (Str.string_match goal_re line 0);
              let g = Str.matched_group 1 line in
              Hashtbl.replace tbl g label)
      tasks;
    tbl
  in
  let write_text path content =
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in
  let config, main, env, datadir_opt = setup_env () in
  let filter =
    Whyconf.parse_filter_prover prover
    |> Whyconf.filter_prover_with_shortcut config
  in
  let fallback_z3 () =
    let is_z3 =
      String.equal (String.lowercase_ascii prover) "z3"
    in
    if not is_z3 then None
    else
      match datadir_opt with
      | None -> None
      | Some datadir ->
          let driver_file = Filename.concat datadir "drivers/z3.drv" in
          if not (Sys.file_exists driver_file) then None
          else
            let z3_ok =
              Sys.command "z3 -version > /dev/null 2>&1" = 0
            in
            if not z3_ok then None
            else
              Some {
                Whyconf.prover = {
                  prover_name = "Z3";
                  prover_version = "";
                  prover_altern = "";
                };
                command = "z3 -smt2 -T:%t %f";
                command_steps = None;
                driver = (None, driver_file);
                in_place = false;
                editor = "";
                interactive = false;
                extra_options = [];
                extra_drivers = [];
              }
  in
  let prover_cfg, use_direct_z3 =
    try (Whyconf.filter_one_prover config filter, false) with
    | Whyconf.ProverNotFound _ ->
        begin match fallback_z3 () with
        | Some prover_cfg -> (prover_cfg, true)
        | None ->
            let _ = Sys.command "why3 config detect > /dev/null 2>&1" in
            let cfg = load_config () in
            (Whyconf.filter_one_prover cfg filter, false)
        end
  in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks = normalize_tasks ~env ~text in
  let limits = {
    Call_provers.empty_limits with
    limit_time = float_of_int timeout;
    limit_mem = Whyconf.memlimit main;
  } in
  let command = Whyconf.get_complete_command prover_cfg ~with_steps:false in
  let prove_with_z3_direct buffer =
    let tmp = Filename.temp_file "why3_task_" ".smt2" in
    let oc = open_out tmp in
    output_string oc (Buffer.contents buffer);
    close_out oc;
    let cmd =
      Printf.sprintf "z3 -smt2 -T:%d %s" timeout (Filename.quote tmp)
    in
    let ic = Unix.open_process_in cmd in
    let output =
      try input_line ic with End_of_file -> ""
    in
    ignore (Unix.close_process_in ic);
    Sys.remove tmp;
    let out = String.lowercase_ascii output in
    if String.equal out "unsat" then Call_provers.Valid
    else if String.equal out "sat" then Call_provers.Invalid
    else if String.equal out "unknown" then Call_provers.Unknown "unknown"
    else Call_provers.Failure output
  in
  let goal_labels =
    let tasks = dump_why3_tasks ~text in
    extract_goal_labels_from_tasks tasks
  in
  prove_tasks_with_details
    ~write_text
    ~driver
    ~main
    ~limits
    ~command
    ~use_direct_z3
    ~prove_with_z3_direct
    ~goal_labels
    ~vc_ids_ordered
    ~on_goal_start
    ~on_goal_done
    tasks

let prove_text_detailed ?(timeout=30) ~(prover:string) ~(text:string) () :
  summary * (string * string * float * string option * string * string option) list =
  let noop_start _ _ = () in
  let noop_done _ _ _ _ _ _ _ = () in
  prove_text_detailed_with_callbacks
    ~timeout
    ~prover
    ~text
    ~vc_ids_ordered:None
    ~on_goal_start:noop_start
    ~on_goal_done:noop_done
    ()
