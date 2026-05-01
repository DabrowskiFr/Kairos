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

type run_output = {
  why_text : string;
  why_spans : (int * (int * int)) list;
  vc_text : string;
  vc_spans_ordered : Pipeline_types.text_span list;
  smt_text : string;
  smt_spans_ordered : Pipeline_types.text_span list;
  vc_ids_ordered : int list;
  vc_locs : (int * Loc.loc) list;
  vc_locs_ordered : Loc.loc list;
  goals : Pipeline_types.goal_info list;
  proof_traces : Pipeline_types.proof_trace list;
}

let diagnostic_for_trace ~(status : string) ~(goal_text : string)
    ~(native_core : Why_native_probe.native_unsat_core option)
    ~(native_probe : Why_native_probe.native_solver_probe option) :
    Pipeline_types.proof_diagnostic =
  let status_norm = String.lowercase_ascii (String.trim status) in
  let native_probe_status =
    Option.map (fun (probe : Why_native_probe.native_solver_probe) -> probe.status) native_probe
  in
  let native_probe_detail =
    Option.bind native_probe (fun (probe : Why_native_probe.native_solver_probe) -> probe.detail)
  in
  let native_probe_model =
    Option.bind native_probe (fun (probe : Why_native_probe.native_solver_probe) -> probe.model_text)
  in
  let category, probable_cause, suggestions, detail =
    match (status_norm, native_probe_status, native_probe_model) with
    | (_, _, Some _) ->
        ( "counterexample_found",
          Some "The native solver produced a satisfying model for the negated VC.",
          [ "Inspect the native model first, then compare against the VC and source intent." ],
          Printf.sprintf "Goal `%s` is falsifiable: the native solver returned a concrete model."
            goal_text )
    | ("valid" | "proved"), _, _ ->
        ( "proved",
          Some "This VC was discharged successfully.",
          [ "No action required." ],
          Printf.sprintf "Goal `%s` was proved successfully." goal_text )
    | "timeout", _, _ ->
        ( "solver_timeout",
          Some "The solver reached its time limit before closing this VC.",
          [ "Retry with a larger timeout and inspect the generated VC." ],
          Printf.sprintf "Goal `%s` timed out." goal_text )
    | "unknown", _, _ ->
        ( "solver_inconclusive",
          Some
            (match native_probe_detail with
            | Some detail -> Printf.sprintf "The solver returned an inconclusive result (%s)." detail
            | None -> "The solver returned an inconclusive result."),
          [ "Inspect VC/SMT artifacts to identify unsupported or hard patterns." ],
          Printf.sprintf "Goal `%s` is inconclusive." goal_text )
    | "invalid", _, _ ->
        ( "counterexample_found",
          Some "The VC is falsifiable: the solver established the negated obligation as satisfiable.",
          [ "Inspect the failing VC and SMT dump first." ],
          Printf.sprintf "Goal `%s` is falsifiable under the current assumptions." goal_text )
    | _ ->
        ( "solver_failure",
          Some
            (match native_probe_detail with
            | Some detail -> Printf.sprintf "The prover failed before a conclusive result (%s)." detail
            | None -> "The prover failed before a conclusive result."),
          [ "Inspect the dumped SMT task and prover configuration." ],
          Printf.sprintf "Goal `%s` failed without a conclusive proof result." goal_text )
  in
  {
    category;
    summary = category;
    detail;
    probable_cause;
    missing_elements = [];
    goal_symbols = [];
    analysis_method =
      (match native_core with
      | Some core ->
          Printf.sprintf
            "Native SMT unsat core recovered from %s on hid-named assertions, then remapped to Kairos hypotheses"
            core.solver
      | None when native_probe_model <> None ->
          "Native SMT model recovered from the targeted solver on the focused VC"
      | None -> "Status-based diagnostic without structured provenance mapping");
    solver_detail = native_probe_detail;
    native_unsat_core_solver =
      Option.map (fun (core : Why_native_probe.native_unsat_core) -> core.solver) native_core;
    native_unsat_core_hypothesis_ids =
      (match native_core with Some core -> core.hypothesis_ids | None -> []);
    native_counterexample_solver =
      Option.bind native_probe (fun (probe : Why_native_probe.native_solver_probe) ->
          match probe.model_text with Some _ -> Some probe.solver | None -> None);
    native_counterexample_model = native_probe_model;
    kairos_core_hypotheses = [];
    why3_noise_hypotheses = [];
    relevant_hypotheses = [];
    context_hypotheses = [];
    unused_hypotheses = [];
    suggestions;
    limitations =
      [
        "This diagnostic view is status-oriented and does not rely on provenance/origin graph mapping.";
        "Native counterexample extraction currently relies on a direct Z3 SMT replay path when available.";
      ];
  }

let build_goal_results ~(cfg : Pipeline_types.config) ~ptree
    ~(vc_ids_ordered : int list) ~normalized_tasks :
    (int * string * string * float * string option * string option) list =
  if cfg.prove && not cfg.wp_only then
    let finished = ref [] in
    let _ =
      Why_contract_prove.prove_ptree_with_events ~timeout:cfg.timeout_s ptree
        ~should_cancel:(fun () -> false)
        ~on_goal_start:(fun _ -> ())
        ~on_goal_done:(fun ev ->
          let idx = ev.goal_index in
          let r = ev.result in
          let status = Proof_status_render.of_prover_answer r.prover_result.pr_answer in
          let vcid =
            match List.nth_opt vc_ids_ordered idx with
            | Some id -> Some (string_of_int id)
            | None -> None
          in
          finished :=
            (idx, r.goal_name, status, r.prover_result.pr_time, r.dump_path, vcid)
            :: !finished)
    in
    List.sort (fun (a, _, _, _, _, _) (b, _, _, _, _, _) -> compare a b) !finished
  else
    List.mapi
      (fun idx _task ->
        let vcid = List.nth vc_ids_ordered idx in
        let stable_id = Printf.sprintf "vc-%03d" (idx + 1) in
        (idx, stable_id, "pending", 0.0, None, Some (string_of_int vcid)))
      normalized_tasks

let build_proof_traces ~(cfg : Pipeline_types.config) ~ptree ~normalized_tasks
    ~(goal_results : (int * string * string * float * string option * string option) list)
    ~(vc_ids_ordered : int list)
    ~(vc_spans_ordered : Pipeline_types.text_span list)
    ~(smt_spans_ordered : Pipeline_types.text_span list) :
    Pipeline_types.proof_trace list =
  let goal_result_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
  List.iter
    (fun ((idx, _, _, _, _, _) as goal_result) ->
      Hashtbl.replace goal_result_tbl idx goal_result)
    goal_results;
  List.mapi (fun idx _task -> idx) normalized_tasks
  |> List.filter_map (fun idx ->
         let _goal_idx, goal_name, status, time_s, dump_path, raw_vcid =
           match Hashtbl.find_opt goal_result_tbl idx with
           | Some goal -> goal
           | None ->
               let fallback_id = Printf.sprintf "vc-%03d" (idx + 1) in
               ( idx,
                 fallback_id,
                 "pending",
                 0.0,
                 None,
                 Some (string_of_int (List.nth vc_ids_ordered idx)) )
         in
         let stable_id = Printf.sprintf "vc-%03d" (idx + 1) in
         let native_core, native_probe =
           if not cfg.compute_proof_diagnostics then (None, None)
           else
             match String.lowercase_ascii status with
             | "valid" | "proved" -> (None, None)
             | "pending" -> (None, None)
             | _ ->
                 let native_probe =
                   Why_native_probe.native_solver_probe_for_goal_of_ptree
                     ~timeout:cfg.timeout_s ~ptree ~goal_index:idx ()
                 in
                 (None, native_probe)
         in
         let diagnostic = diagnostic_for_trace ~status ~goal_text:goal_name ~native_core ~native_probe in
         Some
           {
             Pipeline_types.goal_index = idx;
             stable_id;
             goal_name;
             status;
             solver_status =
               (match native_probe with Some probe -> probe.status | None -> status);
             time_s;
             source = "";
             node = None;
             transition = None;
             obligation_kind = "unknown";
             obligation_family = None;
             obligation_category = None;
             vc_id = raw_vcid;
             source_span = None;
             why_span = None;
             vc_span = List.nth_opt vc_spans_ordered idx;
             smt_span = List.nth_opt smt_spans_ordered idx;
             dump_path;
             diagnostic;
           })

let run ~(cfg : Pipeline_types.config) ~(instrumentation : Ir.node_ir list) :
    (run_output, Pipeline_types.error) result =
  try
    let t_why_gen = Unix.gettimeofday () in
    let why_ast = Why_compile.compile_program_ast_from_ir_nodes instrumentation in
    let ptree = why_ast.Why_compile.mlw in
    let why_text, why_spans = Why_text_render.emit_program_ast_with_spans why_ast in
    External_timing.record_why_gen ~elapsed_s:(Unix.gettimeofday () -. t_why_gen);
    let t_vc_smt = Unix.gettimeofday () in
    let vc_tasks = Why_task_dump_render.dump_why3_tasks_with_attrs_of_ptree ~ptree in
    let vc_text, vc_spans_ordered =
      if cfg.generate_vc_text then
        Pipeline_outputs_helpers.join_blocks_with_spans
          ~sep:"\n(* ---- goal ---- *)\n" vc_tasks
      else ("", [])
    in
    let smt_tasks = Why_task_dump_render.dump_smt2_tasks_of_ptree ~ptree in
    let smt_text, smt_spans_ordered =
      if cfg.generate_smt_text then
        Pipeline_outputs_helpers.join_blocks_with_spans
          ~sep:"\n; ---- goal ----\n" smt_tasks
      else ("", [])
    in
    let _cfg, _main, env, _datadir_opt = Why_task_support.setup_env () in
    let normalized_tasks = Why_task_support.normalize_tasks_of_ptree ~env ~ptree in
    let goal_count = List.length normalized_tasks in
    let vc_ids_ordered = List.init goal_count (fun i -> i + 1) in
    let vc_locs, vc_locs_ordered = ([], []) in
    let goal_results =
      build_goal_results ~cfg ~ptree ~vc_ids_ordered ~normalized_tasks
    in
    External_timing.record_vc_smt ~elapsed_s:(Unix.gettimeofday () -. t_vc_smt);
    let proof_traces, goals =
      if cfg.collect_traceability then
        let traces =
          build_proof_traces ~cfg ~ptree ~normalized_tasks ~goal_results ~vc_ids_ordered
            ~vc_spans_ordered ~smt_spans_ordered
        in
        let goals =
          List.map
            (fun (trace : Pipeline_types.proof_trace) ->
              ( trace.goal_name,
                trace.status,
                trace.time_s,
                trace.dump_path,
                trace.vc_id ))
            traces
        in
        (traces, goals)
      else
        let goals =
          List.map
            (fun (_idx, goal_name, status, time_s, dump_path, vcid) ->
              (goal_name, status, time_s, dump_path, vcid))
            goal_results
        in
        ([], goals)
    in
    Ok
      {
        why_text;
        why_spans;
        vc_text;
        vc_spans_ordered;
        smt_text;
        smt_spans_ordered;
        vc_ids_ordered;
        vc_locs;
        vc_locs_ordered;
        goals;
        proof_traces;
      }
  with exn -> Error (Pipeline_types.Flow_error (Printexc.to_string exn))
