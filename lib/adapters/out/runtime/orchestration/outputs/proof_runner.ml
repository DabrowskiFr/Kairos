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

let run ~(cfg : Pipeline_types.config) ~(instrumentation : Ir.node_ir list) :
    (run_output, Pipeline_types.error) result =
  try
    let progress = Proof_progress_output.open_csv cfg.proof_progress_path in
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
        if Proof_traces.needed cfg then
          Proof_traces.build_fast ~attributions:(Lazy.force attributions)
            goal_results
        else []
      in
      let goals =
        if proof_traces = [] then
          Proof_traces.goals_of_goal_results goal_results
        else Proof_traces.goals_of_proof_traces proof_traces
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
          Proof_text_blocks.join_with_spans
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
          Proof_text_blocks.join_with_spans ~sep:"\n; ---- goal ----\n"
            smt_tasks
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
        Proof_traces.build_from_normalized_tasks ~cfg ~ptree:proof_ptree
          ~normalized_tasks
          ~attributions:(Lazy.force attributions) ~goal_results ~vc_ids_ordered
          ~vc_spans_ordered ~smt_spans_ordered
      in
      let goals = Proof_traces.goals_of_proof_traces proof_traces in
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
