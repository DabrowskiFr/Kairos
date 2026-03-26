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

type result = { status : int; summary : summary }

type sequent_term = {
  text : string;
  symbols : string list;
  operators : string list;
  quantifiers : string list;
  has_arithmetic : bool;
  term_size : int;
  hypothesis_ids : int list;
  origin_labels : string list;
  hypothesis_kind : string option;
}

type structured_sequent = {
  hypotheses : sequent_term list;
  goal : sequent_term;
}

type failing_hypothesis_core = {
  kept_hypothesis_ids : int list;
  removed_hypothesis_ids : int list;
}

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

let empty_summary = { total = 0; valid = 0; invalid = 0; unknown = 0; timeout = 0; failure = 0 }

let finalize_summary summary =
  let total =
    summary.valid + summary.invalid + summary.unknown + summary.timeout + summary.failure
  in
  { summary with total }

let add_answer summary (answer : Call_provers.prover_answer) =
  match answer with
  | Call_provers.Valid -> { summary with valid = summary.valid + 1 }
  | Call_provers.Invalid -> { summary with invalid = summary.invalid + 1 }
  | Call_provers.Timeout -> { summary with timeout = summary.timeout + 1 }
  | Call_provers.StepLimitExceeded -> { summary with timeout = summary.timeout + 1 }
  | Call_provers.Unknown _ -> { summary with unknown = summary.unknown + 1 }
  | Call_provers.OutOfMemory -> { summary with failure = summary.failure + 1 }
  | Call_provers.Failure _ -> { summary with failure = summary.failure + 1 }
  | Call_provers.HighFailure _ -> { summary with failure = summary.failure + 1 }

let tasks_of_text ~(env : Env.env) ~(filename : string) ~(text : string) =
  let lexbuf = Lexing.from_string text in
  Loc.set_file filename lexbuf;
  let parsed = Lexer.parse_mlw_file lexbuf in
  let mods = Typing.type_mlw_file env [] filename parsed in
  Wstdlib.Mstr.fold
    (fun _ m acc -> List.rev_append (Task.split_theory m.Pmodule.mod_theory None None) acc)
    mods []
  |> List.rev

let apply_transform name env tasks =
  List.concat_map (fun task -> Trans.apply_transform name env task) tasks

let normalize_tasks ~(env : Env.env) ~(text : string) : Task.task list =
  tasks_of_text ~env ~filename:"<generated>" ~text |> apply_transform "split_vc" env

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

let extract_hypothesis_ids_from_attrs (attrs : Ident.Sattr.t) : int list =
  Ident.Sattr.elements attrs
  |> List.filter_map (fun attr ->
         let s = attr.Ident.attr_string in
         let prefix = "hid:" in
         let plen = String.length prefix in
         if String.length s >= plen && String.sub s 0 plen = prefix then
           int_of_string_opt (String.sub s plen (String.length s - plen))
         else None)

let unique_preserve_order_strings xs =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun x ->
      if x = "" || Hashtbl.mem seen x then false
      else (
        Hashtbl.replace seen x ();
        true))
    xs

let unique_preserve_order_ints xs =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun x ->
      if Hashtbl.mem seen x then false
      else (
        Hashtbl.replace seen x ();
        true))
    xs

let take n xs =
  let rec loop acc remaining = function
    | _ when remaining <= 0 -> List.rev acc
    | [] -> List.rev acc
    | x :: rest -> loop (x :: acc) (remaining - 1) rest
  in
  loop [] n xs

let status_of_answer = function
  | Call_provers.Valid -> "valid"
  | Call_provers.Invalid -> "invalid"
  | Call_provers.Timeout -> "timeout"
  | Call_provers.StepLimitExceeded -> "timeout"
  | Call_provers.Unknown _ -> "unknown"
  | Call_provers.OutOfMemory -> "oom"
  | Call_provers.Failure _ -> "failure"
  | Call_provers.HighFailure _ -> "failure"

let slurp_process_output (ic : in_channel) : string list =
  let rec loop acc =
    match input_line ic with
    | line -> loop (line :: acc)
    | exception End_of_file -> List.rev acc
  in
  loop []

let classify_z3_lines (lines : string list) : Call_provers.prover_answer =
  let normalize s = String.lowercase_ascii (String.trim s) in
  let rec pick = function
    | [] -> None
    | line :: rest ->
        let s = normalize line in
        if s = "unsat" || s = "sat" || s = "unknown" then Some s else pick rest
  in
  match pick (List.rev lines) with
  | Some "unsat" -> Call_provers.Valid
  | Some "sat" -> Call_provers.Invalid
  | Some "unknown" -> Call_provers.Unknown "unknown"
  | Some other -> Call_provers.Failure other
  | None -> Call_provers.Failure (String.concat "\n" lines)

let prove_single_task_status ~(driver : Driver.driver) ~(main : Whyconf.main)
    ~(limits : Call_provers.resource_limits) ~(command : string) ~(use_direct_z3 : bool)
    ~(prove_with_z3_direct : Buffer.t -> Call_provers.prover_answer) (task : Task.task) : string =
  let prepared = Driver.prepare_task driver task in
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  let printing_info = Driver.print_task_prepared driver fmt prepared in
  Format.pp_print_flush fmt ();
  let goal_name =
    try
      let pr = Task.task_goal prepared in
      pr.Decl.pr_name.Ident.id_string
    with _ -> "goal"
  in
  let answer =
    if use_direct_z3 then prove_with_z3_direct buffer
    else
      let call =
        Driver.prove_buffer_prepared ~command ~config:main ~limits ~theory_name:"generated"
          ~goal_name ~get_model:printing_info driver buffer
      in
      let result = Call_provers.wait_on_call call in
      result.Call_provers.pr_answer
  in
  status_of_answer answer

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

let normalize_tasks_with_wids ~(env : Env.env) ~(text : string) : (Task.task * int list) list =
  let tasks0 = tasks_of_text ~env ~filename:"<generated>" ~text in
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

let rec prove_text ?(timeout = 30) ?prover_cmd ~(prover : string) ~(text : string) () : result =
  let write_text path content =
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in
  let config, main, env, datadir_opt = setup_env () in
  let filter = Whyconf.parse_filter_prover prover |> Whyconf.filter_prover_with_shortcut config in
  let fallback_z3 () =
    let is_z3 = String.equal (String.lowercase_ascii prover) "z3" in
    if not is_z3 then None
    else
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
  in
  let ensure_prover cfg =
    try (Whyconf.filter_one_prover cfg filter, false)
    with Whyconf.ProverNotFound _ ->
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
  let tasks_with_wids = normalize_tasks_with_wids ~env ~text in
  let limits =
    {
      Call_provers.empty_limits with
      limit_time = float_of_int timeout;
      limit_mem = Whyconf.memlimit main;
    }
  in
  let override_cmd =
    match prover_cmd with Some s when String.trim s <> "" -> Some s | _ -> None
  in
  let command =
    match override_cmd with
    | Some cmd -> cmd
    | None -> Whyconf.get_complete_command prover_cfg ~with_steps:false
  in
  let use_direct_z3 =
    if override_cmd <> None then false
    else use_direct_z3 || String.equal (String.lowercase_ascii prover) "z3"
  in
  let prove_with_z3_direct buffer =
    let tmp = Filename.temp_file "why3_task_" ".smt2" in
    let oc = open_out tmp in
    output_string oc (Buffer.contents buffer);
    close_out oc;
    let cmd = Printf.sprintf "z3 -smt2 -T:%d %s" timeout (Filename.quote tmp) in
    let ic = Unix.open_process_in cmd in
    let output_lines = slurp_process_output ic in
    ignore (Unix.close_process_in ic);
    Sys.remove tmp;
    classify_z3_lines output_lines
  in
  let summary, _details =
    prove_tasks_with_details ~write_text ~driver ~main ~limits ~command ~use_direct_z3
      ~prove_with_z3_direct ~goal_labels:(Hashtbl.create 0) ~vc_ids_ordered:None
      ~selected_goal_index:None
      ~should_cancel:(fun () -> false)
      ~on_goal_start:(fun _ _ -> ())
      ~on_goal_done:(fun _ _ _ _ _ _ _ -> ())
      tasks_with_wids
  in
  let status =
    if summary.invalid + summary.unknown + summary.timeout + summary.failure = 0 then 0 else 1
  in
  { status; summary }

and prove_tasks_with_details ~(write_text : string -> string -> unit) ~(driver : Driver.driver)
    ~(main : Whyconf.main) ~(limits : Call_provers.resource_limits) ~(command : string)
    ~(use_direct_z3 : bool) ~(prove_with_z3_direct : Buffer.t -> Call_provers.prover_answer)
    ~(goal_labels : (string, string) Hashtbl.t) ~(vc_ids_ordered : int list option)
    ~(selected_goal_index : int option)
    ~(should_cancel : unit -> bool)
    ~(on_goal_start : int -> string -> unit)
    ~(on_goal_done :
       int -> string -> string -> float -> string option -> string -> string option -> unit)
    (tasks_with_wids : (Task.task * int list) list) :
    summary * (string * string * float * string option * string * string option) list =
  let indexed_tasks =
    List.mapi (fun i tw -> (i, tw)) tasks_with_wids
    |> (fun xs ->
         match selected_goal_index with
         | None -> xs
         | Some k -> List.filter (fun (i, _) -> i = k) xs)
  in
  let total_tasks = List.length indexed_tasks in
  let rec loop pos acc details = function
    | [] -> (finalize_summary acc, List.rev details)
    | _ when should_cancel () -> (finalize_summary acc, List.rev details)
    | (orig_idx, (task, seed_wids)) :: rest ->
        if pos = 0 || pos = total_tasks - 1 || (pos + 1) mod 10 = 0 then
          Log.stage_info (Some Stage_names.Prove)
            (Printf.sprintf "proving goal %d/%d" (pos + 1) total_tasks)
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
        on_goal_start orig_idx goal;
        if should_cancel () then (finalize_summary acc, List.rev details)
        else
        let t0 = Unix.gettimeofday () in
        let answer =
          if use_direct_z3 then prove_with_z3_direct buffer
          else
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
            write_text tmp (Buffer.contents buffer);
            Log.warning ~stage:Stage_names.Prove
              (Printf.sprintf "goal %d/%d failed (%s); dumped to %s" (pos + 1) total_tasks
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
            Some tmp)
          else None
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
          | None -> ( match Hashtbl.find_opt goal_labels goal with Some lbl -> lbl | None -> "")
        in
        let vcid =
          match vc_ids_ordered with
          | Some ids -> begin
              match List.nth_opt ids orig_idx with Some id -> Some (string_of_int id) | None -> None
            end
          | None ->
              let why_ids =
                if seed_wids <> [] then seed_wids
                else
                  try task_wids_deep prepared with _ -> []
              in
              if why_ids = [] then None
              else
                let vc_id = Provenance.fresh_id () in
                Provenance.add_parents ~child:vc_id ~parents:why_ids;
                Some (string_of_int vc_id)
        in
        on_goal_done orig_idx goal status elapsed dump_path provenance vcid;
        if should_cancel () then
          ( finalize_summary (add_answer acc answer),
            List.rev ((goal, status, elapsed, dump_path, provenance, vcid) :: details) )
        else
          loop (pos + 1) (add_answer acc answer)
            ((goal, status, elapsed, dump_path, provenance, vcid) :: details)
            rest
  in
  loop 0 empty_summary [] indexed_tasks

let dump_why3_tasks ~(text : string) : string list =
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

let dump_why3_tasks_with_attrs ~(text : string) : string list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = normalize_tasks ~env ~text in
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

let task_goal_wids ~(text : string) : int list list =
  let _config, _main, env, _datadir_opt = setup_env () in
  normalize_tasks_with_wids ~env ~text |> List.map snd

let task_state_pairs ~(text : string) : (string * string) option list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = normalize_tasks ~env ~text in
  let is_vars_name s =
    let n = String.length s in
    n >= 4 && String.sub s 0 4 = "vars"
  in
  let vars_index s =
    if s = "vars" then Some 0
    else
      let n = String.length s in
      if n > 4 && is_vars_name s then
        int_of_string_opt (String.sub s 4 (n - 4))
      else None
  in
  let var_of_st_term (t : Term.term) : string option =
    match t.Term.t_node with
    | Term.Tapp (ls_st, [ vterm ]) when ls_st.Term.ls_name.Ident.id_string = "st" -> (
        match vterm.Term.t_node with
        | Term.Tapp (vls, []) ->
            let v = vls.Term.ls_name.Ident.id_string in
            if is_vars_name v then Some v else None
        | _ -> None)
    | _ -> None
  in
  let const_of_term (t : Term.term) : string option =
    match t.Term.t_node with
    | Term.Tapp (ls, []) ->
        let n = ls.Term.ls_name.Ident.id_string in
        if is_vars_name n then None else Some n
    | _ -> None
  in
  let add_unique_pair acc (a, b) =
    if List.exists (fun (x, y) -> x = a && y = b) acc then acc else (a, b) :: acc
  in
  let infer_one (task : Task.task) : (string * string) option =
    let var_state : (string, string) Hashtbl.t = Hashtbl.create 8 in
    let var_aliases = ref [] in
    let record_eq (a : Term.term) (b : Term.term) =
      match (var_of_st_term a, const_of_term b, var_of_st_term b, const_of_term a) with
      | Some v, Some st, _, _ ->
          if not (Hashtbl.mem var_state v) then Hashtbl.add var_state v st
      | _, _, Some v, Some st ->
          if not (Hashtbl.mem var_state v) then Hashtbl.add var_state v st
      | Some va, None, Some vb, None ->
          var_aliases := add_unique_pair !var_aliases (va, vb)
      | _ -> ()
    in
    let walk_term (t : Term.term) =
      ignore
        (Term.t_fold
           (fun () tm ->
             match tm.Term.t_node with
             | Term.Tapp (ls, [ a; b ]) when Term.ls_equal ls Term.ps_equ -> record_eq a b
             | _ -> ();
             ())
           () t)
    in
    begin try walk_term (Task.task_goal_fmla task) with _ -> ()
    end;
    Task.task_decls task
    |> List.iter (fun decl ->
           match decl.Decl.d_node with
           | Decl.Dprop (_kind, _pr, t) -> walk_term t
           | _ -> ());
    let changed = ref true in
    while !changed do
      changed := false;
      List.iter
        (fun (a, b) ->
          match (Hashtbl.find_opt var_state a, Hashtbl.find_opt var_state b) with
          | Some sa, None ->
              Hashtbl.replace var_state b sa;
              changed := true
          | None, Some sb ->
              Hashtbl.replace var_state a sb;
              changed := true
          | _ -> ())
        !var_aliases
    done;
    let pairs =
      Hashtbl.to_seq var_state |> List.of_seq
      |> List.filter_map (fun (v, st) -> Option.map (fun i -> (i, st)) (vars_index v))
      |> List.sort (fun (i, _) (j, _) -> compare i j)
    in
    match pairs with
    | [] -> None
    | (i0, src) :: rest ->
        let dst =
          match List.rev ((i0, src) :: rest) with
          | (_, d) :: _ -> d
          | [] -> src
        in
        Some (src, dst)
  in
  List.map infer_one tasks

let task_sequents ~(text : string) : (string list * string) list =
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

let task_structured_sequents ~(text : string) : structured_sequent list =
  let _config, _main, env, _datadir_opt = setup_env () in
  let tasks = normalize_tasks ~env ~text in
  let term_to_string (t : Term.term) =
    let buf = Buffer.create 256 in
    let fmt = Format.formatter_of_buffer buf in
    Pretty.print_term fmt t;
    Format.pp_print_flush fmt ();
    Buffer.contents buf
  in
  let is_arithmetic_name name =
    match name with
    | "+" | "-" | "*" | "/" | "<" | "<=" | ">" | ">=" -> true
    | _ -> String.equal name "infix +" || String.equal name "infix -" || String.equal name "infix *"
  in
  let analyze_term (t : Term.term) : sequent_term =
    let symbols = ref [] in
    let operators = ref [] in
    let quantifiers = ref [] in
    let has_arithmetic = ref false in
    let term_size = ref 0 in
    let hypothesis_ids = ref [] in
    let origin_labels = ref [] in
    let hypothesis_kind = ref None in
    let push acc value = acc := value :: !acc in
    let add_attrs (attrs : Ident.Sattr.t) =
      hypothesis_ids := extract_hypothesis_ids_from_attrs attrs @ !hypothesis_ids;
      origin_labels := origin_labels_of_attrs attrs @ !origin_labels;
      match (!hypothesis_kind, hyp_kind_of_attrs attrs) with
      | None, Some kind -> hypothesis_kind := Some kind
      | _ -> ()
    in
    add_attrs t.Term.t_attrs;
    let record_ls (ls : Term.lsymbol) =
      let name = ls.Term.ls_name.Ident.id_string in
      if name <> "" then (
        push symbols name;
        if ls.Term.ls_value <> None then push operators name;
        if is_arithmetic_name name then has_arithmetic := true)
    in
    let record_vs (vs : Term.vsymbol) =
      let name = vs.Term.vs_name.Ident.id_string in
      if name <> "" then push symbols name
    in
    ignore
      (Term.t_fold
         (fun () tm ->
           incr term_size;
           add_attrs tm.Term.t_attrs;
           begin
             match tm.Term.t_node with
             | Term.Tvar vs -> record_vs vs
             | Term.Tapp (ls, args) ->
                 record_ls ls;
                 if args = [] && String.length ls.Term.ls_name.Ident.id_string > 0 then
                   push operators ls.Term.ls_name.Ident.id_string
             | Term.Tquant (q, tq) ->
                 let qname =
                   match q with
                   | Term.Tforall -> "forall"
                   | Term.Texists -> "exists"
                 in
                 push quantifiers qname;
                 ignore tq
             | Term.Tlet (_tb, _body) -> push operators "let"
             | Term.Tcase (_head, branches) ->
                 if branches <> [] then push operators "case"
             | Term.Tif (_c, _t1, _t2) -> push operators "if"
             | Term.Teps _tb -> push quantifiers "eps"
             | _ -> ()
           end;
           ())
         () t);
    {
      text = term_to_string t;
      symbols = unique_preserve_order_strings (List.rev !symbols);
      operators = unique_preserve_order_strings (List.rev !operators);
      quantifiers = unique_preserve_order_strings (List.rev !quantifiers);
      has_arithmetic = !has_arithmetic;
      term_size = !term_size;
      hypothesis_ids = unique_preserve_order_ints (List.rev !hypothesis_ids);
      origin_labels = unique_preserve_order_strings (List.rev !origin_labels);
      hypothesis_kind = !hypothesis_kind;
    }
  in
  let task_to_structured task =
    let goal_pr = Task.task_goal task in
    let goal_term = Task.task_goal_fmla task in
    let hypotheses =
      Task.task_decls task
      |> List.filter_map (fun decl ->
             match decl.Decl.d_node with
             | Decl.Dprop (_kind, pr, t) ->
                 if Decl.pr_equal pr goal_pr then None
                 else
                   let has_local_news = not (Ident.Sid.is_empty decl.Decl.d_news) in
                   if has_local_news then Some (analyze_term t) else None
             | _ -> None)
    in
    { hypotheses; goal = analyze_term goal_term }
  in
  List.map task_to_structured tasks

let minimize_failing_hypotheses ?(timeout = 5) ?prover_cmd ~(prover : string) ~(text : string)
    ~(goal_index : int) () : failing_hypothesis_core option =
  let config, main, env, datadir_opt = setup_env () in
  let tasks_with_wids = normalize_tasks_with_wids ~env ~text in
  match List.nth_opt tasks_with_wids goal_index with
  | None -> None
  | Some (task, _wids) ->
      let filter = Whyconf.parse_filter_prover prover |> Whyconf.filter_prover_with_shortcut config in
      let fallback_z3 () =
        let is_z3 = String.equal (String.lowercase_ascii prover) "z3" in
        if not is_z3 then None
        else
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
      in
      let prover_cfg, use_direct_z3 =
        try (Whyconf.filter_one_prover config filter, false)
        with Whyconf.ProverNotFound _ ->
          begin match fallback_z3 () with
          | Some prover_cfg -> (prover_cfg, true)
          | None ->
              let _ = Sys.command "why3 config detect > /dev/null 2>&1" in
              let cfg = load_config () in
              (Whyconf.filter_one_prover cfg filter, false)
          end
      in
      let driver = Driver.load_driver_for_prover main env prover_cfg in
      let limits =
        {
          Call_provers.empty_limits with
          limit_time = float_of_int timeout;
          limit_mem = Whyconf.memlimit main;
        }
      in
      let override_cmd =
        match prover_cmd with Some s when String.trim s <> "" -> Some s | _ -> None
      in
      let command =
        match override_cmd with
        | Some cmd -> cmd
        | None -> Whyconf.get_complete_command prover_cfg ~with_steps:false
      in
      let use_direct_z3 = if override_cmd <> None then false else use_direct_z3 in
      let prove_with_z3_direct buffer =
        let tmp = Filename.temp_file "why3_task_" ".smt2" in
        let oc = open_out tmp in
        output_string oc (Buffer.contents buffer);
        close_out oc;
        let cmd = Printf.sprintf "z3 -smt2 -T:%d %s" timeout (Filename.quote tmp) in
        let ic = Unix.open_process_in cmd in
        let output = try input_line ic with End_of_file -> "" in
        ignore (Unix.close_process_in ic);
        Sys.remove tmp;
        let out = String.lowercase_ascii output in
        if String.equal out "unsat" then Call_provers.Valid
        else if String.equal out "sat" then Call_provers.Invalid
        else if String.equal out "unknown" then Call_provers.Unknown "unknown"
        else Call_provers.Failure output
      in
      let original_status =
        prove_single_task_status ~driver ~main ~limits ~command ~use_direct_z3 ~prove_with_z3_direct
          task
      in
      if original_status = "valid" then None
      else
        let decl_hids (decl : Decl.decl) =
          match decl.Decl.d_node with
          | Decl.Dprop (_kind, _pr, t) -> extract_hypothesis_ids_from_attrs t.Term.t_attrs
          | _ -> []
        in
        let tdecl_hids (td : Theory.tdecl) =
          match td.Theory.td_node with
          | Theory.Decl decl -> decl_hids decl
          | _ -> []
        in
        let goal_td, prefix = Task.task_separate_goal task in
        let prefix_tdecls = Task.task_tdecls prefix in
        let candidate_hids =
          prefix_tdecls
          |> List.concat_map tdecl_hids
          |> unique_preserve_order_ints
          |> take 10
        in
        if candidate_hids = [] then
          Some { kept_hypothesis_ids = []; removed_hypothesis_ids = [] }
        else
          let rebuild_task active_hids =
            let active_tbl = Hashtbl.create 16 in
            List.iter (fun id -> Hashtbl.replace active_tbl id ()) active_hids;
            let keep_tdecl td =
              let hids = tdecl_hids td in
              hids = [] || List.exists (fun id -> Hashtbl.mem active_tbl id) hids
            in
            let rebuilt_prefix =
              List.fold_left
                (fun acc td -> if keep_tdecl td then Task.add_tdecl acc td else acc)
                None prefix_tdecls
            in
            Task.add_tdecl rebuilt_prefix goal_td
          in
          let keeps_failure active_hids =
            let rebuilt = rebuild_task active_hids in
            let status =
              prove_single_task_status ~driver ~main ~limits ~command ~use_direct_z3
                ~prove_with_z3_direct rebuilt
            in
            status <> "valid"
          in
          let split_in_halves xs =
            let len = List.length xs in
            let half = max 1 (len / 2) in
            let rec take_drop acc n ys =
              if n <= 0 then (List.rev acc, ys)
              else
                match ys with
                | [] -> (List.rev acc, [])
                | y :: rest -> take_drop (y :: acc) (n - 1) rest
            in
            take_drop [] half xs
          in
          let rec eliminate_groups active removed =
            if List.length active <= 1 then (active, removed)
            else
              let left, right = split_in_halves active in
              let try_remove group =
                let remaining = List.filter (fun id -> not (List.mem id group)) active in
                if remaining <> [] && keeps_failure remaining then Some (remaining, List.rev_append group removed)
                else None
              in
              match try_remove left with
              | Some (active', removed') -> eliminate_groups active' removed'
              | None -> begin
                  match try_remove right with
                  | Some (active', removed') -> eliminate_groups active' removed'
                  | None -> (active, removed)
                end
          in
          let rec greedy active removed = function
            | [] -> { kept_hypothesis_ids = active; removed_hypothesis_ids = List.rev removed }
            | hid :: rest ->
                let active_without = List.filter (fun id -> id <> hid) active in
                if active_without <> [] && keeps_failure active_without then
                  greedy active_without (hid :: removed) rest
                else greedy active removed rest
          in
          let grouped_active, grouped_removed = eliminate_groups candidate_hids [] in
          Some (greedy grouped_active grouped_removed grouped_active)

let dump_smt2_tasks ~(prover : string) ~(text : string) : string list =
  let config, main, env, datadir_opt = setup_env () in
  let filter = Whyconf.parse_filter_prover prover |> Whyconf.filter_prover_with_shortcut config in
  let fallback_z3 () =
    let is_z3 = String.equal (String.lowercase_ascii prover) "z3" in
    if not is_z3 then None
    else
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
  in
  let prover_cfg =
    try Whyconf.filter_one_prover config filter
    with Whyconf.ProverNotFound _ ->
      begin match fallback_z3 () with
      | Some prover_cfg -> prover_cfg
      | None ->
          let _ = Sys.command "why3 config detect > /dev/null 2>&1" in
          let cfg = load_config () in
          Whyconf.filter_one_prover cfg filter
      end
  in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks_with_wids = normalize_tasks_with_wids ~env ~text in
  let task_to_smt2 task =
    let prepared = Driver.prepare_task driver task in
    let buffer = Buffer.create 4096 in
    let fmt = Format.formatter_of_buffer buffer in
    ignore (Driver.print_task_prepared driver fmt prepared);
    Format.pp_print_flush fmt ();
    Buffer.contents buffer
  in
  List.map (fun (t, _wids) -> task_to_smt2 t) tasks_with_wids

let top_level_asserts (text : string) : (int * int) list =
  let len = String.length text in
  let rec loop i depth start acc =
    if i >= len then List.rev acc
    else
      match text.[i] with
      | '(' ->
          if depth = 0 && i + 7 <= len && String.sub text i 7 = "(assert" then
            loop (i + 1) 1 i acc
          else loop (i + 1) (depth + 1) start acc
      | ')' ->
          if depth = 1 && start >= 0 then loop (i + 1) 0 (-1) ((start, i + 1) :: acc)
          else loop (i + 1) (max 0 (depth - 1)) start acc
      | _ -> loop (i + 1) depth start acc
  in
  loop 0 0 (-1) []

let hypothesis_ids_of_task (task : Task.task) : int option list =
  let goal_pr = Task.task_goal task in
  Task.task_decls task
  |> List.filter_map (fun decl ->
         match decl.Decl.d_node with
         | Decl.Dprop (_kind, pr, t) ->
             if Decl.pr_equal pr goal_pr then None
             else
               let has_local_news = not (Ident.Sid.is_empty decl.Decl.d_news) in
               if not has_local_news then None
               else
                 let ids = extract_hypothesis_ids_from_attrs t.Term.t_attrs |> unique_preserve_order_ints in
                 Some (match ids with id :: _ -> Some id | [] -> None)
         | _ -> None)

let build_named_unsat_core_smt ~(task : Task.task) ~(smt_text : string) : string option =
  let hypothesis_ids = hypothesis_ids_of_task task in
  let assert_spans = top_level_asserts smt_text in
  let assert_count = List.length assert_spans in
  let hypothesis_count = List.length hypothesis_ids in
  if hypothesis_count = 0 || assert_count < hypothesis_count + 1 then None
  else
    let named_start = assert_count - (hypothesis_count + 1) in
    let named_hyp_asserts =
      assert_spans |> List.filteri (fun idx _ -> idx >= named_start && idx < named_start + hypothesis_count)
    in
    if List.length named_hyp_asserts <> hypothesis_count then None
    else
      let b = Buffer.create (String.length smt_text + 512) in
      Buffer.add_string b "(set-option :produce-unsat-cores true)\n";
      let cursor = ref 0 in
      List.iteri
        (fun idx (start_pos, end_pos) ->
          Buffer.add_substring b smt_text !cursor (start_pos - !cursor);
          let original = String.sub smt_text start_pos (end_pos - start_pos) in
          (match List.nth_opt hypothesis_ids idx with
          | Some (Some hid) ->
              let prefix = "(assert " in
              let plen = String.length prefix in
              if String.length original > plen && String.sub original 0 plen = prefix then (
                let body = String.sub original plen (String.length original - plen - 1) in
                Buffer.add_string b
                  (Printf.sprintf "(assert (! %s :named hid_%d))" body hid))
              else Buffer.add_string b original
          | _ -> Buffer.add_string b original);
          cursor := end_pos)
        named_hyp_asserts;
      Buffer.add_substring b smt_text !cursor (String.length smt_text - !cursor);
      Buffer.add_string b "\n(get-unsat-core)\n";
      Some (Buffer.contents b)

let rewrite_smt_for_model ~(smt_text : string) : string =
  let lines = String.split_on_char '\n' smt_text in
  let filtered =
    List.filter
      (fun line ->
        let trimmed = String.trim line in
        trimmed <> "(get-model)" && trimmed <> "(get-info :reason-unknown)")
      lines
  in
  let b = Buffer.create (String.length smt_text + 128) in
  Buffer.add_string b "(set-option :produce-models true)\n";
  List.iter (fun line -> Buffer.add_string b line; Buffer.add_char b '\n') filtered;
  Buffer.add_string b "(get-info :reason-unknown)\n";
  Buffer.add_string b "(get-model)\n";
  Buffer.contents b

let run_z3_script ?(timeout = 5) ~(smt_text : string) () : string list =
  let tmp = Filename.temp_file "kairos_native_solver_" ".smt2" in
  let oc = open_out tmp in
  output_string oc smt_text;
  close_out oc;
  let cmd = Printf.sprintf "z3 -smt2 -T:%d %s 2>&1" timeout (Filename.quote tmp) in
  let ic = Unix.open_process_in cmd in
  let rec read_lines acc =
    match input_line ic with
    | line -> read_lines (line :: acc)
    | exception End_of_file -> List.rev acc
  in
  let lines = read_lines [] in
  ignore (Unix.close_process_in ic);
  Sys.remove tmp;
  lines

let classify_native_solver_output (lines : string list) : string * string option * string option =
  let status =
    match lines with
    | first :: _ ->
        let s = String.lowercase_ascii (String.trim first) in
        if s = "sat" then "invalid"
        else if s = "unsat" then "valid"
        else if s = "unknown" then "unknown"
        else if String.length s >= 5 && String.sub s 0 5 = "error" then "solver_error"
        else "failure"
    | [] -> "failure"
  in
  let rest =
    match lines with
    | _ :: xs ->
        let joined = String.concat "\n" xs |> String.trim in
        if joined = "" then None else Some joined
    | [] -> None
  in
  let detail, model_text =
    match status with
    | "invalid" ->
        let model =
          match rest with
          | Some txt when String.contains txt '(' -> Some txt
          | _ -> None
        in
        (Some "The native solver produced a satisfying model for the negated VC.", model)
    | "unknown" -> (rest, None)
    | "solver_error" | "failure" -> (rest, None)
    | _ -> (rest, None)
  in
  (status, detail, model_text)

let native_unsat_core_for_goal ?(timeout = 5) ~(prover : string) ~(text : string) ~(goal_index : int)
    () : native_unsat_core option =
  if String.lowercase_ascii prover <> "z3" then None
  else
    let _config, _main, env, _datadir_opt = setup_env () in
    let tasks_with_wids = normalize_tasks_with_wids ~env ~text in
    match (List.nth_opt tasks_with_wids goal_index, List.nth_opt (dump_smt2_tasks ~prover ~text) goal_index) with
    | Some (task, _), Some smt_text -> (
        match build_named_unsat_core_smt ~task ~smt_text with
        | None -> None
        | Some named_smt ->
            let tmp = Filename.temp_file "kairos_unsat_core_" ".smt2" in
            let oc = open_out tmp in
            output_string oc named_smt;
            close_out oc;
            let cmd = Printf.sprintf "z3 -smt2 -T:%d %s" timeout (Filename.quote tmp) in
            let ic = Unix.open_process_in cmd in
            let rec read_lines acc =
              match input_line ic with
              | line -> read_lines (line :: acc)
              | exception End_of_file -> List.rev acc
            in
            let lines = read_lines [] in
            ignore (Unix.close_process_in ic);
            Sys.remove tmp;
            match lines with
            | status :: core_line :: _ when String.lowercase_ascii (String.trim status) = "unsat" ->
                let ids =
                  Str.global_substitute (Str.regexp "[()]+") (fun _ -> " ") core_line
                    |> String.split_on_char ' '
                    |> List.filter_map (fun tok ->
                           let tok = String.trim tok in
                           let prefix = "hid_" in
                           let plen = String.length prefix in
                           if String.length tok > plen && String.sub tok 0 plen = prefix then
                             int_of_string_opt (String.sub tok plen (String.length tok - plen))
                           else None)
                  |> unique_preserve_order_ints
                in
                Some { solver = "z3"; hypothesis_ids = ids; smt_text = named_smt }
            | _ -> None)
    | _ -> None

let native_solver_probe_for_goal ?(timeout = 5) ~(prover : string) ~(text : string)
    ~(goal_index : int) () : native_solver_probe option =
  if String.lowercase_ascii prover <> "z3" then None
  else
    match List.nth_opt (dump_smt2_tasks ~prover ~text) goal_index with
    | None -> None
    | Some smt_text ->
        let rewritten = rewrite_smt_for_model ~smt_text in
        let status, detail, model_text =
          run_z3_script ~timeout ~smt_text:rewritten () |> classify_native_solver_output
        in
        Some { solver = "z3"; status; detail; model_text; smt_text = rewritten }

let prove_text_detailed_with_callbacks ?(timeout = 30) ?prover_cmd ?selected_goal_index
    ?(should_cancel = fun () -> false) ~(prover : string)
    ~(text : string) ~(vc_ids_ordered : int list option) ~(on_goal_start : int -> string -> unit)
    ~(on_goal_done :
       int -> string -> string -> float -> string option -> string -> string option -> unit) () :
    summary * (string * string * float * string option * string * string option) list =
  let extract_goal_labels_from_tasks tasks =
    let tbl = Hashtbl.create 64 in
    let comment_re = Str.regexp "^\\s*\\(\\* \\(.*\\) \\*\\)\\s*$" in
    let goal_re = Str.regexp "^\\s*goal[ \t]+\\([A-Za-z0-9_]+\\)\\b" in
    let extract_label task =
      let labels =
        String.split_on_char '\n' task
        |> List.filter_map (fun line ->
            if Str.string_match comment_re line 0 then Some (Str.matched_group 2 line) else None)
      in
      match labels with [] -> "" | x :: _ -> x
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
  let filter = Whyconf.parse_filter_prover prover |> Whyconf.filter_prover_with_shortcut config in
  let fallback_z3 () =
    let is_z3 = String.equal (String.lowercase_ascii prover) "z3" in
    if not is_z3 then None
    else
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
  in
  let prover_cfg, use_direct_z3 =
    try (Whyconf.filter_one_prover config filter, false)
    with Whyconf.ProverNotFound _ ->
      begin match fallback_z3 () with
      | Some prover_cfg -> (prover_cfg, true)
      | None ->
          let _ = Sys.command "why3 config detect > /dev/null 2>&1" in
          let cfg = load_config () in
          (Whyconf.filter_one_prover cfg filter, false)
      end
  in
  let driver = Driver.load_driver_for_prover main env prover_cfg in
  let tasks_with_wids = normalize_tasks_with_wids ~env ~text in
  let limits =
    {
      Call_provers.empty_limits with
      limit_time = float_of_int timeout;
      limit_mem = Whyconf.memlimit main;
    }
  in
  let override_cmd =
    match prover_cmd with Some s when String.trim s <> "" -> Some s | _ -> None
  in
  let command =
    match override_cmd with
    | Some cmd -> cmd
    | None -> Whyconf.get_complete_command prover_cfg ~with_steps:false
  in
  let use_direct_z3 =
    if override_cmd <> None then false
    else use_direct_z3 || String.equal (String.lowercase_ascii prover) "z3"
  in
  let prove_with_z3_direct buffer =
    let tmp = Filename.temp_file "why3_task_" ".smt2" in
    let oc = open_out tmp in
    output_string oc (Buffer.contents buffer);
    close_out oc;
    let cmd = Printf.sprintf "z3 -smt2 -T:%d %s" timeout (Filename.quote tmp) in
    let ic = Unix.open_process_in cmd in
    let output_lines = slurp_process_output ic in
    ignore (Unix.close_process_in ic);
    Sys.remove tmp;
    classify_z3_lines output_lines
  in
  let goal_labels =
    let tasks = dump_why3_tasks ~text in
    extract_goal_labels_from_tasks tasks
  in
  prove_tasks_with_details ~write_text ~driver ~main ~limits ~command ~use_direct_z3
    ~prove_with_z3_direct ~goal_labels ~vc_ids_ordered ~selected_goal_index ~should_cancel ~on_goal_start
    ~on_goal_done tasks_with_wids
