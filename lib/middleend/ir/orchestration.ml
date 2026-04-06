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

open Ast

let ( let* ) = Result.bind

type run_metrics = {
  product_s : float;
  canonical_s : float;
}

type initial_ir = {
  nodes : Ir.node_ir list;
  analyses : (Ast.ident * Product_build.analysis) list;
}

let program_transitions_of_ast_node (node : Ast.node) : Ir.transition list =
  Ir_transition.prioritized_program_transitions_of_node node

let source_nodes_by_name (source_program : Ast.program) : (Ast.ident * Ast.node) list =
  List.map (fun (node : Ast.node) -> (node.semantics.sem_nname, node)) source_program

let source_node_of_name ~(source_nodes : (Ast.ident * Ast.node) list) ~(node_name : Ast.ident) :
    (Ast.node, string) result =
  Result_utils.find_assoc
    ~missing:(fun name -> Printf.sprintf "Missing source AST node for IR node %s" name)
    node_name source_nodes

let build_node_analysis ~(automata : Automata_generation.node_builds)
    ~(program_transitions : Ir.transition list) (node : Ir.node_ir) :
    (Product_build.analysis, string) result =
  let* build =
    Result_utils.find_assoc
      ~missing:(fun node_name -> Printf.sprintf "Missing automata build for IR node %s" node_name)
      node.context.semantics.sem_nname automata
  in
  Ok (Product_build.analyze_node ~build ~node ~program_transitions)

let build_analyses ~(automata : Automata_generation.node_builds)
    ~(source_nodes : (Ast.ident * Ast.node) list) (nodes : Ir.node_ir list) :
    ((Ast.ident * Product_build.analysis) list, string) result =
  nodes
  |> List.map (fun (node : Ir.node_ir) ->
         let* source_node =
           source_node_of_name ~source_nodes ~node_name:node.context.semantics.sem_nname
         in
         let analysis =
           build_node_analysis ~automata
             ~program_transitions:(program_transitions_of_ast_node source_node)
             node
         in
         Result.map (fun value -> (node.context.semantics.sem_nname, value)) analysis)
  |> Result_utils.all

let build_initial_ir ~(automata : Automata_generation.node_builds) (parsed : Stage_types.parsed) :
    (initial_ir, string) result =
  let source_nodes = source_nodes_by_name parsed in
  let context_nodes = From_ast.of_ast_program parsed in
  let* analyses = build_analyses ~automata ~source_nodes context_nodes in
  let* minimal_generations =
    Minimal.build_program ~analyses
      ~program_transitions_of_node:(fun node_name ->
        let* source_node = source_node_of_name ~source_nodes ~node_name in
        Ok (program_transitions_of_ast_node source_node))
      context_nodes
  in
  let minimal_nodes =
    Minimal.apply_program ~minimal_generations context_nodes
  in
  Ok { nodes = minimal_nodes; analyses }

let analysis_of_node ~(analyses : (Ast.ident * Product_build.analysis) list) (node : Ir.node_ir) :
    (Product_build.analysis, string) result =
  Result_utils.find_assoc
    ~missing:(fun node_name -> Printf.sprintf "Missing product analysis for IR node %s" node_name)
    node.context.semantics.sem_nname analyses

let collect_formula_origins (nodes : Ir.node_ir list) : (int * Formula_origin.t option) list =
  let collect_formula acc (formula : Ir.summary_formula) =
    (formula.meta.oid, formula.meta.origin) :: acc
  in
  let collect_product_transition acc (transition : Ir.product_step_summary) =
    transition.requires |> List.fold_left collect_formula acc |> fun acc ->
    transition.ensures |> List.fold_left collect_formula acc |> fun acc ->
    transition.safe_cases
    |> List.fold_left
         (fun acc (case : Ir.safe_product_case) ->
           collect_formula acc case.admissible_guard)
         acc
    |> fun acc ->
    transition.unsafe_cases
    |> List.fold_left
         (fun acc (case : Ir.unsafe_product_case) -> collect_formula acc case.excluded_guard)
         acc
  in
  nodes
  |> List.fold_left
       (fun acc (node : Ir.node_ir) ->
         List.fold_left collect_product_transition acc node.summaries)
       []
  |> List.rev

let formulas_info_of_nodes (nodes : Ir.node_ir list) : Ir.formulas_info =
  { formula_origin_map = collect_formula_origins nodes; warnings = [] }

let product_state_is_live ~(analysis : Product_build.analysis) (st : Product_types.product_state) :
    bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let product_step_is_live_requested ~(analysis : Product_build.analysis)
    (step : Product_types.product_step) : bool =
  let src_not_g_bad =
    analysis.guarantee_bad_idx < 0 || step.src.guarantee_state <> analysis.guarantee_bad_idx
  in
  let dst_not_a_bad =
    analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx
  in
  src_not_g_bad && dst_not_a_bad

let accumulate_case_counts (summaries : Ir.product_step_summary list) :
    int * int * int =
  List.fold_left
    (fun (safe_acc, bad_a_acc, bad_g_acc) (summary : Ir.product_step_summary) ->
      (safe_acc + List.length summary.safe_cases, bad_a_acc,
       bad_g_acc + List.length summary.unsafe_cases))
    (0, 0, 0)
    summaries

let merge_instrumentation_info (left : Stage_info.instrumentation_info)
    (right : Stage_info.instrumentation_info) : Stage_info.instrumentation_info =
  {
    Stage_info.kernel_ir_nodes = left.kernel_ir_nodes @ right.kernel_ir_nodes;
    exported_node_summaries = left.exported_node_summaries @ right.exported_node_summaries;
    raw_ir_nodes = left.raw_ir_nodes @ right.raw_ir_nodes;
    annotated_ir_nodes = left.annotated_ir_nodes @ right.annotated_ir_nodes;
    verified_ir_nodes = left.verified_ir_nodes @ right.verified_ir_nodes;
    kernel_pipeline_lines = left.kernel_pipeline_lines @ right.kernel_pipeline_lines;
    warnings = left.warnings @ right.warnings;
    guarantee_automaton_lines =
      left.guarantee_automaton_lines @ right.guarantee_automaton_lines;
    assume_automaton_lines = left.assume_automaton_lines @ right.assume_automaton_lines;
    guarantee_automaton_tex =
      if left.guarantee_automaton_tex <> "" then left.guarantee_automaton_tex
      else right.guarantee_automaton_tex;
    assume_automaton_tex =
      if left.assume_automaton_tex <> "" then left.assume_automaton_tex
      else right.assume_automaton_tex;
    product_tex = if left.product_tex <> "" then left.product_tex else right.product_tex;
    product_tex_explicit =
      if left.product_tex_explicit <> "" then left.product_tex_explicit else right.product_tex_explicit;
    canonical_tex = if left.canonical_tex <> "" then left.canonical_tex else right.canonical_tex;
    product_lines = left.product_lines @ right.product_lines;
    canonical_lines = left.canonical_lines @ right.canonical_lines;
    obligations_lines = left.obligations_lines @ right.obligations_lines;
    guarantee_automaton_dot =
      if left.guarantee_automaton_dot <> "" then left.guarantee_automaton_dot
      else right.guarantee_automaton_dot;
    assume_automaton_dot =
      if left.assume_automaton_dot <> "" then left.assume_automaton_dot
      else right.assume_automaton_dot;
    product_dot = if left.product_dot <> "" then left.product_dot else right.product_dot;
    product_dot_explicit =
      if left.product_dot_explicit <> "" then left.product_dot_explicit else right.product_dot_explicit;
    canonical_dot = if left.canonical_dot <> "" then left.canonical_dot else right.canonical_dot;
    require_automata_state_count =
      left.require_automata_state_count + right.require_automata_state_count;
    require_automata_edge_count =
      left.require_automata_edge_count + right.require_automata_edge_count;
    ensures_automata_state_count =
      left.ensures_automata_state_count + right.ensures_automata_state_count;
    ensures_automata_edge_count =
      left.ensures_automata_edge_count + right.ensures_automata_edge_count;
    product_edge_count_full = left.product_edge_count_full + right.product_edge_count_full;
    product_edge_count_live = left.product_edge_count_live + right.product_edge_count_live;
    product_state_count_full = left.product_state_count_full + right.product_state_count_full;
    product_state_count_live = left.product_state_count_live + right.product_state_count_live;
    canonical_summary_count = left.canonical_summary_count + right.canonical_summary_count;
    canonical_case_safe_count =
      left.canonical_case_safe_count + right.canonical_case_safe_count;
    canonical_case_bad_assumption_count =
      left.canonical_case_bad_assumption_count + right.canonical_case_bad_assumption_count;
    canonical_case_bad_guarantee_count =
      left.canonical_case_bad_guarantee_count + right.canonical_case_bad_guarantee_count;
  }

let instrumentation_info_of_node ~(source_node : Ast.node)
    ~(analyses : (Ast.ident * Product_build.analysis) list) (node : Ir.node_ir) :
    (Stage_info.instrumentation_info, string) result =
  let* analysis = analysis_of_node ~analyses node in
  let raw_ir =
    Proof_obligation_raw.build_raw_node ~program_transitions:(program_transitions_of_ast_node source_node)
      node
  in
  let annotated_ir = Proof_obligation_annotate.annotate ~raw:raw_ir ~node in
  let verified_ir =
    {
      (Proof_obligation_lowering.eliminate annotated_ir) with
      product_transitions = node.summaries;
    }
  in
  let rendered =
    Ir_render_product.render ~node_name:node.context.semantics.sem_nname ~analysis
  in
  let rendered_canonical =
    Ir_render_canonical.render ~node_name:node.context.semantics.sem_nname ~analysis ~node
  in
  let kernel_ir =
    Proof_kernel_build.of_node_analysis
      ~node_name:node.context.semantics.sem_nname
      ~source_node
      ~node
      ~analysis
  in
  let exported_summary =
    Proof_kernel_build.export_node_summary ~source_node ~node ~normalized_ir:kernel_ir
  in
  let require_automata_state_count = List.length analysis.assume_state_labels in
  let require_automata_edge_count = List.length analysis.assume_grouped_edges in
  let ensures_automata_state_count = List.length analysis.guarantee_state_labels in
  let ensures_automata_edge_count = List.length analysis.guarantee_grouped_edges in
  let product_edge_count_full = List.length analysis.exploration.steps in
  let product_edge_count_live =
    analysis.exploration.steps
    |> List.filter (product_step_is_live_requested ~analysis)
    |> List.length
  in
  let product_state_count_full = List.length analysis.exploration.states in
  let product_state_count_live =
    analysis.exploration.states
    |> List.filter (product_state_is_live ~analysis)
    |> List.length
  in
  let canonical_summary_count = List.length node.summaries in
  let canonical_case_safe_count, canonical_case_bad_assumption_count,
      canonical_case_bad_guarantee_count =
    accumulate_case_counts node.summaries
  in
  Ok
    {
      Stage_info.kernel_ir_nodes = [ kernel_ir ];
      exported_node_summaries = [ exported_summary ];
      raw_ir_nodes = [ raw_ir ];
      annotated_ir_nodes = [ annotated_ir ];
      verified_ir_nodes = [ verified_ir ];
      kernel_pipeline_lines = Ir_render_kernel.render_node_ir kernel_ir;
      warnings = [];
      guarantee_automaton_lines = rendered.guarantee_automaton_lines;
      assume_automaton_lines = rendered.assume_automaton_lines;
      guarantee_automaton_tex = rendered.guarantee_automaton_tex;
      assume_automaton_tex = rendered.assume_automaton_tex;
      product_tex = rendered.product_tex;
      product_tex_explicit = rendered.product_tex_explicit;
      canonical_tex = rendered_canonical.canonical_tex;
      product_lines = rendered.product_lines;
      canonical_lines = rendered_canonical.canonical_lines;
      obligations_lines = rendered.obligations_lines;
      guarantee_automaton_dot = rendered.guarantee_automaton_dot;
      assume_automaton_dot = rendered.assume_automaton_dot;
      product_dot = rendered.product_dot;
      product_dot_explicit = rendered.product_dot_explicit;
      canonical_dot = rendered_canonical.canonical_dot;
      require_automata_state_count;
      require_automata_edge_count;
      ensures_automata_state_count;
      ensures_automata_edge_count;
      product_edge_count_full;
      product_edge_count_live;
      product_state_count_full;
      product_state_count_live;
      canonical_summary_count;
      canonical_case_safe_count;
      canonical_case_bad_assumption_count;
      canonical_case_bad_guarantee_count;
    }

let instrumentation_info_of_ir ~(automata : Automata_generation.node_builds)
    ~(source_program : Ast.program) (program : Ir.program_ir)
    : (Stage_info.instrumentation_info, string) result =
  let source_nodes = source_nodes_by_name source_program in
  let* analyses = build_analyses ~automata ~source_nodes program.nodes in
  let node_results =
    program.nodes
    |> List.map (fun (node : Ir.node_ir) ->
           let* source_node =
             source_node_of_name ~source_nodes ~node_name:node.context.semantics.sem_nname
           in
           instrumentation_info_of_node ~source_node ~analyses node)
  in
  node_results |> Result_utils.all
  |> Result.map (List.fold_left merge_instrumentation_info Stage_info.empty_instrumentation_info)

let run_with_metrics (parsed : Stage_types.parsed) (automata : Automata_generation.node_builds) :
    ((Ir.program_ir * run_metrics), string) result =
  (* Phase 1: initial IR construction = AST context projection + minimal summaries. *)
  let t_product = Unix.gettimeofday () in
  let* initial_ir = build_initial_ir ~automata parsed in
  let product_s = Unix.gettimeofday () -. t_product in
  let t_canonical = Unix.gettimeofday () in
  let nodes =
    initial_ir.nodes
    |> fun nodes -> Pre.apply_program ~pre_generations:(Pre.build_program nodes) nodes
    |> fun nodes -> Post.apply_program ~post_generations:(Post.build_program nodes) nodes
    |> Proof_obligation_raw.apply_program
    |> Proof_obligation_lowering.apply_program
  in
  let canonical_s = Unix.gettimeofday () -. t_canonical in
  let program = ({ nodes; formulas_info = formulas_info_of_nodes nodes } : Ir.program_ir) in
  Ok (program, { product_s; canonical_s })

let run (parsed : Stage_types.parsed) (automata : Automata_generation.node_builds) :
    (Ir.program_ir, string) result =
  run_with_metrics parsed automata |> Result.map fst
