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

type proof_progress = { emit : Pipeline_types.goal_info -> unit }

type proof_goal_result = {
  result_index : int;
  result_goal_name : string;
  result_status : string;
  result_time_s : float;
  result_timing : Why_contract_prove.goal_timing;
  result_dump_path : string option;
  result_vcid : string option;
}

let zero_goal_timing : Why_contract_prove.goal_timing =
  {
    prepare_s = 0.0;
    print_s = 0.0;
    spawn_s = 0.0;
    wait_s = 0.0;
    solver_s = 0.0;
  }

let open_proof_progress = function
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

let proof_status_is_valid status =
  match String.lowercase_ascii status with
  | "valid" | "proved" -> true
  | _ -> false

type goal_attribution = {
  source : string;
  node : string option;
  transition : string option;
  obligation_kind : string;
  obligation_family : string option;
  obligation_category : string option;
}

let product_state_source (st : Ir.product_state) =
  Printf.sprintf "(P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let attribution_step_class
    (step_class : Why_runtime_view.runtime_step_class) =
  match step_class with
  | Why_runtime_view.StepSafe ->
      ("product-step-safe", Some "guarantee-progress")
  | Why_runtime_view.StepBadGuarantee ->
      ("product-step-bad-guarantee", Some "guarantee-violation-exclusion")

let goal_name_lookup_key (goal_name : string) =
  match String.index_opt goal_name '\'' with
  | None -> goal_name
  | Some idx -> String.sub goal_name 0 idx

let attribution_of_step ~node_name ~index
    (step : Why_runtime_view.runtime_product_transition_view) =
  let obligation_kind, obligation_category =
    attribution_step_class step.step_class
  in
  let source =
    Printf.sprintf
      "helper=%s;product_src=%s;product_dst=%s;requires=%d;local_requires=%d;\
       propagates=%d;ensures=%d;forbidden=%d"
      (Why_compile.product_step_helper_name ~index step)
      (product_state_source step.product_src)
      (product_state_source step.product_dst)
      (List.length step.requires)
      (List.length step.local_requires)
      (List.length step.propagates)
      (List.length step.ensures)
      (List.length step.forbidden)
  in
  {
    source;
    node = Some node_name;
    transition =
      Some
        (Printf.sprintf "%s -> %s (%s)" step.src_state step.dst_state
           step.transition_id);
    obligation_kind;
    obligation_family = Some "product-step";
    obligation_category;
  }

let attribution_of_group ~node_name ~index ~group_size
    (step : Why_runtime_view.runtime_product_transition_view) =
  let obligation_kind, obligation_category =
    attribution_step_class step.step_class
  in
  let source =
    Printf.sprintf
      "helper=%s;group_size=%d;product_src=%s;requires=%d;local_requires=%d;\
       propagates=%d;ensures=%d;forbidden=%d"
      (Why_compile.product_step_group_helper_name ~index step)
      group_size
      (product_state_source step.product_src)
      (List.length step.requires)
      (List.length step.local_requires)
      (List.length step.propagates)
      (List.length step.ensures)
      (List.length step.forbidden)
  in
  {
    source;
    node = Some node_name;
    transition =
      Some
        (Printf.sprintf "%s -> %s (%s)" step.src_state step.dst_state
           step.transition_id);
    obligation_kind;
    obligation_family = Some "product-step-group";
    obligation_category;
  }

let build_attribution_table
    ~(opts : Pipeline_types.proof_optimizations)
    (instrumentation : Ir.node_ir list) :
    (string, goal_attribution) Hashtbl.t =
  let table = Hashtbl.create 256 in
  let add_step_attributions (runtime : Why_runtime_view.t) =
    List.iteri
      (fun index step ->
        let helper_name = Why_compile.product_step_helper_name ~index step in
        Hashtbl.replace table helper_name
          (attribution_of_step ~node_name:runtime.node_name ~index step))
      runtime.product_transitions
  in
  let add_group_attributions (runtime : Why_runtime_view.t) =
    let groups = Hashtbl.create 128 in
    let order = ref [] in
    let group_key (step : Why_runtime_view.runtime_product_transition_view) =
      let t =
        Why_runtime_view.transition_of_product_step
          ~simplify_runtime_actions:opts.simplify_why3_runtime_actions step
      in
      (step.step_class, t)
    in
    runtime.product_transitions
    |> List.iteri (fun index step ->
        let key = group_key step in
        if not (Hashtbl.mem groups key) then order := key :: !order;
        let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
        Hashtbl.replace groups key ((index, step) :: previous));
    List.rev !order
    |> List.iter (fun key ->
           let indexed_steps = Hashtbl.find groups key |> List.rev in
           if List.length indexed_steps > 1 then
             indexed_steps
             |> List.iter (fun (index, representative) ->
                    let helper_name =
                      Why_compile.product_step_group_helper_name ~index
                        representative
                    in
                    Hashtbl.replace table helper_name
                      (attribution_of_group ~node_name:runtime.node_name ~index
                         ~group_size:(List.length indexed_steps) representative)))
  in
  instrumentation
  |> List.iter (fun (node : Ir.node_ir) ->
         let runtime =
           Why_runtime_view.of_ir_node
             ~simplify_runtime_actions:opts.simplify_why3_runtime_actions
             ~slice_transition_bodies:opts.slice_why3_transition_bodies node
         in
         add_step_attributions runtime;
         if opts.group_why3_product_steps then add_group_attributions runtime);
  table

let attribution_for_goal attributions goal_name =
  Hashtbl.find_opt attributions (goal_name_lookup_key goal_name)

let apply_attribution attributions goal_name
    (trace : Pipeline_types.proof_trace) =
  match attribution_for_goal attributions goal_name with
  | None -> trace
  | Some attribution ->
      {
        trace with
        source = attribution.source;
        node = attribution.node;
        transition = attribution.transition;
        obligation_kind = attribution.obligation_kind;
        obligation_family = attribution.obligation_family;
        obligation_category = attribution.obligation_category;
      }

let goal_name_of_task task =
  Why_contract_prove.goal_name_of_prepared_task task

let build_goal_results ~progress ~(cfg : Pipeline_types.config)
    ~(vc_ids_ordered : int list) ~normalized_tasks :
    proof_goal_result list =
  if cfg.prove && not cfg.wp_only then
    let finished = ref [] in
    let stop_requested = ref false in
    let should_cancel () = cfg.stop_on_first_nonvalid && !stop_requested in
    let proof_jobs = if cfg.stop_on_first_nonvalid then 1 else cfg.proof_jobs in
    let _ =
      Why_contract_prove.prove_tasks_with_events ~timeout:cfg.timeout_s
        ~jobs:proof_jobs ~dump_failed_smt:cfg.dump_failed_smt ~should_cancel
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
          Option.iter
            (fun (progress : proof_progress) ->
              progress.emit
                (r.goal_name, status, r.prover_result.pr_time, r.dump_path, vcid))
            progress;
          finished :=
            {
              result_index = idx;
              result_goal_name = r.goal_name;
              result_status = status;
              result_time_s = r.prover_result.pr_time;
              result_timing = r.timing;
              result_dump_path = r.dump_path;
              result_vcid = vcid;
            }
            :: !finished;
          if cfg.stop_on_first_nonvalid && not (proof_status_is_valid status) then
            stop_requested := true)
        normalized_tasks
    in
    List.sort
      (fun left right -> compare left.result_index right.result_index)
      !finished
  else
    List.mapi
      (fun idx task ->
        let vcid = List.nth vc_ids_ordered idx in
        let goal_name =
          try goal_name_of_task task with _ -> Printf.sprintf "vc-%03d" (idx + 1)
        in
        {
          result_index = idx;
          result_goal_name = goal_name;
          result_status = "pending";
          result_time_s = 0.0;
          result_timing = zero_goal_timing;
          result_dump_path = None;
          result_vcid = Some (string_of_int vcid);
        })
      normalized_tasks

let build_proof_traces ~(cfg : Pipeline_types.config) ~ptree ~normalized_tasks
    ~attributions
    ~(goal_results : proof_goal_result list)
    ~(vc_ids_ordered : int list)
    ~(vc_spans_ordered : Pipeline_types.text_span list)
    ~(smt_spans_ordered : Pipeline_types.text_span list) :
    Pipeline_types.proof_trace list =
  let goal_result_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
  List.iter
    (fun goal_result ->
      Hashtbl.replace goal_result_tbl goal_result.result_index goal_result)
    goal_results;
  List.mapi (fun idx _task -> idx) normalized_tasks
  |> List.filter_map (fun idx ->
         let goal_result =
           match Hashtbl.find_opt goal_result_tbl idx with
           | Some goal -> goal
           | None ->
               let fallback_id = Printf.sprintf "vc-%03d" (idx + 1) in
               {
                 result_index = idx;
                 result_goal_name = fallback_id;
                 result_status = "pending";
                 result_time_s = 0.0;
                 result_timing = zero_goal_timing;
                 result_dump_path = None;
                 result_vcid = Some (string_of_int (List.nth vc_ids_ordered idx));
               }
         in
         let goal_name = goal_result.result_goal_name in
         let status = goal_result.result_status in
         let time_s = goal_result.result_time_s in
         let timing = goal_result.result_timing in
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
             vc_id = goal_result.result_vcid;
             source_span = None;
             why_span = None;
             vc_span = List.nth_opt vc_spans_ordered idx;
             smt_span = List.nth_opt smt_spans_ordered idx;
             dump_path = goal_result.result_dump_path;
             diagnostic;
           }
         in
         Some (apply_attribution attributions goal_name trace))

let build_fast_proof_traces ~attributions
    (goal_results : proof_goal_result list) :
    Pipeline_types.proof_trace list =
  goal_results
  |> List.map (fun goal_result ->
         let idx = goal_result.result_index in
         let goal_name = goal_result.result_goal_name in
         let status = goal_result.result_status in
         let time_s = goal_result.result_time_s in
         let timing = goal_result.result_timing in
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
             vc_id = goal_result.result_vcid;
             source_span = None;
             why_span = None;
             vc_span = None;
             smt_span = None;
             dump_path = goal_result.result_dump_path;
             diagnostic =
               diagnostic_for_trace ~status ~goal_text:goal_name ~native_core:None
                 ~native_probe:None;
           }
         in
         apply_attribution attributions goal_name trace)

let goals_of_proof_traces (proof_traces : Pipeline_types.proof_trace list) :
    Pipeline_types.goal_info list =
  List.map
    (fun (trace : Pipeline_types.proof_trace) ->
      (trace.goal_name, trace.status, trace.time_s, trace.dump_path, trace.vc_id))
    proof_traces

let run ~(cfg : Pipeline_types.config) ~(instrumentation : Ir.node_ir list) :
    (run_output, Pipeline_types.error) result =
  try
    let progress = open_proof_progress cfg.proof_progress_path in
    let t_why_gen = Unix.gettimeofday () in
    let opts =
      match cfg.proof_encoding with
      | Pipeline_types.Explicit_product -> cfg.proof_optimizations
    in
    let attributions = build_attribution_table ~opts instrumentation in
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
        let finished = ref [] in
        let stop_requested = ref false in
        let should_cancel () = cfg.stop_on_first_nonvalid && !stop_requested in
        let proof_jobs = if cfg.stop_on_first_nonvalid then 1 else cfg.proof_jobs in
        let _ =
          Why_contract_prove.prove_ptrees_with_events ~timeout:cfg.timeout_s
            ~jobs:proof_jobs ~split_vc:true ~dump_failed_smt:cfg.dump_failed_smt
            ~should_cancel ~on_goal_start:(fun _ -> ())
            ~on_goal_done:(fun ev ->
              let idx = ev.Why_contract_prove.goal_index in
              let r = ev.result in
              let status = Proof_status_render.of_prover_answer r.prover_result.pr_answer in
              finished :=
                {
                  result_index = idx;
                  result_goal_name = r.goal_name;
                  result_status = status;
                  result_time_s = r.prover_result.pr_time;
                  result_timing = r.timing;
                  result_dump_path = r.dump_path;
                  result_vcid = Some (string_of_int (idx + 1));
                }
                :: !finished;
              if cfg.stop_on_first_nonvalid && not (proof_status_is_valid status) then
                stop_requested := true)
            module_ptrees
        in
        List.sort
          (fun left right -> Int.compare left.result_index right.result_index)
          !finished
      in
      let vc_ids_ordered =
        List.map (fun goal -> goal.result_index + 1) goal_results
      in
      let proof_traces = build_fast_proof_traces ~attributions goal_results in
      let goals = goals_of_proof_traces proof_traces in
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
          Pipeline_outputs_helpers.join_blocks_with_spans
            ~sep:"\n(* ---- goal ---- *)\n" vc_tasks
        else ("", [])
      in
      let smt_tasks =
        if cfg.generate_smt_text then
          Why_task_dump_render.dump_smt2_tasks_of_tasks normalized_tasks
        else []
      in
      let smt_text, smt_spans_ordered =
        if cfg.generate_smt_text then
          Pipeline_outputs_helpers.join_blocks_with_spans
            ~sep:"\n; ---- goal ----\n" smt_tasks
        else ("", [])
      in
      let goal_count = List.length normalized_tasks in
      let vc_ids_ordered = List.init goal_count (fun i -> i + 1) in
      let vc_locs, vc_locs_ordered = ([], []) in
      let goal_results =
        build_goal_results ~progress ~cfg ~vc_ids_ordered ~normalized_tasks
      in
      External_timing.record_vc_smt ~elapsed_s:(Unix.gettimeofday () -. t_vc_smt);
      let proof_traces =
        build_proof_traces ~cfg ~ptree:proof_ptree ~normalized_tasks ~attributions
          ~goal_results ~vc_ids_ordered
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
