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

module Goal_results = Proof_goal_results

let join_blocks_with_spans ~sep blocks =
  let b = Buffer.create 4096 in
  let spans = ref [] in
  let offset = ref 0 in
  List.iteri
    (fun i s ->
      if i > 0 then (
        Buffer.add_string b sep;
        offset := !offset + String.length sep);
      let start_offset = !offset in
      Buffer.add_string b s;
      offset := !offset + String.length s;
      spans :=
        { Pipeline_types.start_offset = start_offset; end_offset = !offset } :: !spans)
    blocks;
  (Buffer.contents b, List.rev !spans)

let csv_escape field =
  if String.exists (fun c -> c = ',' || c = '"' || c = '\n' || c = '\r') field then
    let b = Buffer.create (String.length field + 8) in
    Buffer.add_char b '"';
    String.iter
      (function
        | '"' -> Buffer.add_string b "\"\""
        | c -> Buffer.add_char b c)
      field;
    Buffer.add_char b '"';
    Buffer.contents b
  else field

let open_proof_progress : string option -> Goal_results.progress option =
  function
  | None | Some "-" -> None
  | Some path ->
      let oc = open_out path in
      output_string oc "index,name,status,time_s,dump_path,vcid\n";
      flush oc;
      let rows = ref 0 in
      let emit (name, status, time_s, dump_path, vcid) =
        incr rows;
        [
          string_of_int !rows;
          name;
          status;
          Printf.sprintf "%.6f" time_s;
          Option.value dump_path ~default:"";
          Option.value vcid ~default:"";
        ]
        |> List.map csv_escape |> String.concat "," |> output_string oc;
        output_char oc '\n';
        flush oc
      in
      Some { emit }

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

let build_proof_traces ~(cfg : Pipeline_types.config) ~ptree ~normalized_tasks
    ~attributions
    ~(goal_results : Proof_goal_results.t list)
    ~(vc_ids_ordered : int list)
    ~(vc_spans_ordered : Pipeline_types.text_span list)
    ~(smt_spans_ordered : Pipeline_types.text_span list) :
    Pipeline_types.proof_trace list =
  let goal_result_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
  List.iter
    (fun goal_result ->
      Hashtbl.replace goal_result_tbl
        goal_result.Goal_results.result_index goal_result)
    goal_results;
  List.mapi (fun idx _task -> idx) normalized_tasks
  |> List.filter_map (fun idx ->
         let goal_result =
           match Hashtbl.find_opt goal_result_tbl idx with
           | Some goal -> goal
           | None ->
               let fallback_id = Printf.sprintf "vc-%03d" (idx + 1) in
               Proof_goal_results.pending ~index:idx ~goal_name:fallback_id
                 ~vcid:(Some (string_of_int (List.nth vc_ids_ordered idx)))
         in
         let goal_name = goal_result.Goal_results.result_goal_name in
         let status = goal_result.Goal_results.result_status in
         let time_s = goal_result.Goal_results.result_time_s in
         let timing = goal_result.Goal_results.result_timing in
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
         let trace =
           {
             Pipeline_types.goal_index = idx;
             stable_id;
             goal_name;
             status;
             solver_status =
               (match native_probe with Some probe -> probe.status | None -> status);
             time_s;
             why3_prepare_s = timing.prepare_s;
             why3_print_s = timing.print_s;
             why3_spawn_s = timing.spawn_s;
             why3_wait_s = timing.wait_s;
             why3_solver_s = timing.solver_s;
             source = "";
             node = None;
             transition = None;
             obligation_kind = "unknown";
             obligation_family = None;
             obligation_category = None;
             vc_id = goal_result.Goal_results.result_vcid;
             source_span = None;
             why_span = None;
             vc_span = List.nth_opt vc_spans_ordered idx;
             smt_span = List.nth_opt smt_spans_ordered idx;
             dump_path = goal_result.Goal_results.result_dump_path;
             diagnostic;
           }
         in
         Some (Proof_goal_attribution.apply attributions ~goal_name trace))

let build_fast_proof_traces ~attributions
    (goal_results : Proof_goal_results.t list) :
    Pipeline_types.proof_trace list =
  goal_results
  |> List.map (fun goal_result ->
         let idx = goal_result.Goal_results.result_index in
         let goal_name = goal_result.Goal_results.result_goal_name in
         let status = goal_result.Goal_results.result_status in
         let time_s = goal_result.Goal_results.result_time_s in
         let timing = goal_result.Goal_results.result_timing in
         let stable_id = Printf.sprintf "vc-%03d" (idx + 1) in
         let trace =
           {
             Pipeline_types.goal_index = idx;
             stable_id;
             goal_name;
             status;
             solver_status = status;
             time_s;
             why3_prepare_s = timing.prepare_s;
             why3_print_s = timing.print_s;
             why3_spawn_s = timing.spawn_s;
             why3_wait_s = timing.wait_s;
             why3_solver_s = timing.solver_s;
             source = "";
             node = None;
             transition = None;
             obligation_kind = "unknown";
             obligation_family = None;
             obligation_category = None;
             vc_id = goal_result.Goal_results.result_vcid;
             source_span = None;
             why_span = None;
             vc_span = None;
             smt_span = None;
             dump_path = goal_result.Goal_results.result_dump_path;
             diagnostic =
               diagnostic_for_trace ~status ~goal_text:goal_name ~native_core:None
                 ~native_probe:None;
           }
         in
         Proof_goal_attribution.apply attributions ~goal_name trace)

let goals_of_proof_traces (proof_traces : Pipeline_types.proof_trace list) :
    Pipeline_types.goal_info list =
  List.map
    (fun (trace : Pipeline_types.proof_trace) ->
      (trace.goal_name, trace.status, trace.time_s, trace.dump_path, trace.vc_id))
    proof_traces

let goals_of_goal_results (goal_results : Proof_goal_results.t list) :
    Pipeline_types.goal_info list =
  List.map Proof_goal_results.to_goal_info goal_results

let proof_traces_needed (cfg : Pipeline_types.config) : bool =
  cfg.collect_ir_metrics || cfg.compute_proof_diagnostics
  || cfg.generate_vc_text || cfg.generate_smt_text
  || Option.is_some cfg.proof_progress_path

let run ~(cfg : Pipeline_types.config) ~(instrumentation : Ir.node_ir list) :
    (run_output, Pipeline_types.error) result =
  try
    let progress = open_proof_progress cfg.proof_progress_path in
    let t_why_gen = Unix.gettimeofday () in
    let opts =
      match cfg.proof_encoding with
      | Pipeline_types.Explicit_product -> cfg.proof_optimizations
    in
    let attributions =
      lazy (Proof_goal_attribution.build ~opts instrumentation)
    in
    let why_ast =
      Why_compile.compile_program_ast_from_ir_nodes
        ~share_why3_facts:opts.share_why3_facts
        ~simplify_why3_formulas:opts.simplify_why3_formulas
        ~slice_why3_transition_bodies:opts.slice_why3_transition_bodies
        ~simplify_why3_runtime_actions:opts.simplify_why3_runtime_actions
        ~deduplicate_why3_terms:opts.deduplicate_why3_terms
        ~group_why3_product_steps:opts.group_why3_product_steps
        ~why3_product_step_group_max_cost:opts.why3_product_step_group_max_cost
        instrumentation
    in
    let proof_ptree = why_ast.Why_compile.mlw in
    let module_ptrees = Why_task_support.module_ptrees_of_ptree proof_ptree in
    let output_why_text, output_why_spans =
      if cfg.generate_why_text then Why_text_render.emit_program_ast_with_spans why_ast
      else ("", [])
    in
    External_timing.record_why_gen ~elapsed_s:(Unix.gettimeofday () -. t_why_gen);
    let t_vc_smt = Unix.gettimeofday () in
    if cfg.prove && Option.is_none progress && not cfg.wp_only && not cfg.generate_vc_text
       && not cfg.generate_smt_text && not cfg.compute_proof_diagnostics
    then
      let goal_results =
        Proof_goal_results.of_module_ptrees_fast ~cfg ~module_ptrees
      in
      let vc_ids_ordered =
        Proof_goal_results.vc_ids_from_result_indices goal_results
      in
      let proof_traces =
        if proof_traces_needed cfg then
          build_fast_proof_traces ~attributions:(Lazy.force attributions)
            goal_results
        else []
      in
      let goals =
        if proof_traces = [] then goals_of_goal_results goal_results
        else goals_of_proof_traces proof_traces
      in
      External_timing.record_vc_smt ~elapsed_s:(Unix.gettimeofday () -. t_vc_smt);
      Ok
        {
          why_text = output_why_text;
          why_spans = output_why_spans;
          vc_text = "";
          vc_spans_ordered = [];
          smt_text = "";
          smt_spans_ordered = [];
          vc_ids_ordered;
          vc_locs = [];
          vc_locs_ordered = [];
          goals;
          proof_traces;
        }
    else
      let _cfg, _main, env, _datadir_opt = Why_task_support.setup_env () in
      let normalized_tasks =
        Why_task_support.normalize_tasks_of_ptrees ~env ~ptrees:module_ptrees
      in
      let vc_tasks =
        if cfg.generate_vc_text then
          Why_task_dump_render.dump_why3_tasks_with_attrs_of_tasks normalized_tasks
        else []
      in
      let vc_text, vc_spans_ordered =
        if cfg.generate_vc_text then
          join_blocks_with_spans ~sep:"\n(* ---- goal ---- *)\n" vc_tasks
        else ("", [])
      in
      let smt_tasks =
        if cfg.generate_smt_text then
          Why_task_dump_render.dump_smt2_tasks_of_tasks normalized_tasks
        else []
      in
      let smt_text, smt_spans_ordered =
        if cfg.generate_smt_text then
          join_blocks_with_spans ~sep:"\n; ---- goal ----\n" smt_tasks
        else ("", [])
      in
      let goal_count = List.length normalized_tasks in
      let vc_ids_ordered = List.init goal_count (fun i -> i + 1) in
      let vc_locs, vc_locs_ordered = ([], []) in
      let goal_results =
        Proof_goal_results.of_normalized_tasks ~progress ~cfg ~vc_ids_ordered
          ~normalized_tasks
      in
      External_timing.record_vc_smt ~elapsed_s:(Unix.gettimeofday () -. t_vc_smt);
      let proof_traces =
        build_proof_traces ~cfg ~ptree:proof_ptree ~normalized_tasks
          ~attributions:(Lazy.force attributions) ~goal_results ~vc_ids_ordered
          ~vc_spans_ordered ~smt_spans_ordered
      in
      let goals = goals_of_proof_traces proof_traces in
      Ok
        {
          why_text = output_why_text;
          why_spans = output_why_spans;
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
