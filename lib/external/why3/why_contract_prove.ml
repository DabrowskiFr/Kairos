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

let extract_hypothesis_ids_from_attrs (attrs : Ident.Sattr.t) : int list =
  Ident.Sattr.elements attrs
  |> List.filter_map (fun attr ->
         let s = attr.Ident.attr_string in
         let prefix = "hid:" in
         let plen = String.length prefix in
         if String.length s >= plen && String.sub s 0 plen = prefix then
           int_of_string_opt (String.sub s plen (String.length s - plen))
         else None)

let unique_preserve_order_ints xs =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun x ->
      if Hashtbl.mem seen x then false
      else (
        Hashtbl.replace seen x ();
        true))
    xs

let status_of_answer = function
  | Call_provers.Valid -> "valid"
  | Call_provers.Invalid -> "invalid"
  | Call_provers.Timeout -> "timeout"
  | Call_provers.StepLimitExceeded -> "timeout"
  | Call_provers.Unknown _ -> "unknown"
  | Call_provers.OutOfMemory -> "oom"
  | Call_provers.Failure _ -> "failure"
  | Call_provers.HighFailure _ -> "failure"

let prover_answer_to_status = status_of_answer

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

let prove_tasks_with_details ~(write_text : string -> string -> unit) ~(driver : Driver.driver)
    ~(main : Whyconf.main) ~(limits : Call_provers.resource_limits) ~(command : string)
    ~(use_direct_z3 : bool) ~(prove_with_z3_direct : Buffer.t -> Call_provers.prover_answer)
    ~(goal_labels : (string, string) Hashtbl.t)
    ~(should_cancel : unit -> bool)
    ~(on_goal_start : goal_start_event -> unit)
    ~(on_goal_done : goal_done_event -> unit)
    (tasks_with_wids : (Task.task * int list) list) :
    goal_proof_result list =
  let indexed_tasks = List.mapi (fun i tw -> (i, tw)) tasks_with_wids in
  let total_tasks = List.length indexed_tasks in
  let rec loop pos details = function
    | [] -> List.rev details
    | _ when should_cancel () -> List.rev details
    | (orig_idx, (task, _seed_wids)) :: rest ->
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
        on_goal_start { goal_index = orig_idx; goal_name = goal };
        if should_cancel () then List.rev details
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
        let provenance =
          let attrs =
            try (Task.task_goal_fmla prepared).Term.t_attrs with _ -> Ident.Sattr.empty
          in
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

let task_to_smt2_with_driver ~(driver : Driver.driver) (task : Task.task) : string =
  let prepared = Driver.prepare_task driver task in
  let buffer = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buffer in
  ignore (Driver.print_task_prepared driver fmt prepared);
  Format.pp_print_flush fmt ();
  Buffer.contents buffer

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

let native_unsat_core_for_goal_of_ptree ?(timeout = 5) ~(ptree : Ptree.mlw_file)
    ~(goal_index : int) () : native_unsat_core option =
  let config, main, env, datadir_opt = setup_env () in
  let tasks_with_wids = normalize_tasks_with_wids_of_ptree ~env ~ptree in
  match List.nth_opt tasks_with_wids goal_index with
  | Some (task, _) -> (
      let prover_cfg = select_z3_prover_cfg ~config ~datadir_opt in
      let driver = Driver.load_driver_for_prover main env prover_cfg in
      let smt_text = task_to_smt2_with_driver ~driver task in
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
      let rewritten = rewrite_smt_for_model ~smt_text in
      let status, detail, model_text =
        run_z3_script ~timeout ~smt_text:rewritten () |> classify_native_solver_output
      in
      Some { solver = "z3"; status; detail; model_text; smt_text = rewritten }

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
  let render_task (task : Task.task) : string =
    let buffer = Buffer.create 4096 in
    let fmt = Format.formatter_of_buffer buffer in
    Pretty.print_task fmt task;
    Format.pp_print_flush fmt ();
    Buffer.contents buffer
  in
  let write_text path content =
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in
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
    let tasks = List.map (fun (task, _wids) -> render_task task) tasks_with_wids in
    extract_goal_labels_from_tasks tasks
  in
  prove_tasks_with_details ~write_text ~driver ~main ~limits ~command ~use_direct_z3:true
    ~prove_with_z3_direct ~goal_labels ~should_cancel ~on_goal_start ~on_goal_done
    tasks_with_wids
