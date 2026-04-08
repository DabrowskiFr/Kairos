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

let program_transitions_of_ast_node (node : Ast.node) : Ir.transition list =
  Ir_transition.prioritized_program_transitions_of_node node

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let guard_fo (g : Ast.iexpr option) : Fo_formula.t =
  match g with
  | None -> Fo_formula.FTrue
  | Some e ->
      Fo_specs.iexpr_to_fo_with_atoms [] e |> simplify_fo

let raw_transition_of_program_transition (t : Ir.transition) : Ir_proof_views.raw_transition =
  {
    core =
      {
        Ir.src_state = t.src_state;
        dst_state = t.dst_state;
        guard_iexpr = t.guard_iexpr;
        body_stmts = t.body_stmts;
      };
    guard = guard_fo t.guard_iexpr;
  }

let build_raw_ir_node ~(program_transitions : Ir.transition list) (node : Ir.node_ir) :
    Ir_proof_views.raw_node =
  {
    core =
      {
        Ir_proof_views.node_name = node.semantics.sem_nname;
        inputs = node.semantics.sem_inputs;
        outputs = node.semantics.sem_outputs;
        locals = node.semantics.sem_locals;
        control_states = node.semantics.sem_states;
        init_state = node.semantics.sem_init_state;
      };
    temporal_layout = node.temporal_layout;
    transitions = List.map raw_transition_of_program_transition program_transitions;
    assumes = node.source_info.assumes;
    guarantees = node.source_info.guarantees;
  }

let annotate_raw_ir_node ~(raw : Ir_proof_views.raw_node) ~(node : Ir.node_ir) :
    Ir_proof_views.annotated_node =
  {
    raw;
    transitions =
      List.map
        (fun (t : Ir_proof_views.raw_transition) ->
          ({ raw = t; clauses = { requires = []; ensures = [] } }
            : Ir_proof_views.annotated_transition))
        raw.transitions;
    init_invariant_goals = node.init_invariant_goals;
  }

let verify_annotated_ir_node ~(annotated : Ir_proof_views.annotated_node)
    ~(product_transitions : Ir.product_step_summary list) : Ir_proof_views.verified_node =
  {
    Ir_proof_views.core = annotated.raw.core;
    transitions =
      List.map
        (fun (t : Ir_proof_views.annotated_transition) ->
          ({
             Ir_proof_views.core = t.raw.core;
             guard = t.raw.guard;
             clauses = t.clauses;
           }
            : Ir_proof_views.verified_transition))
        annotated.transitions;
    product_transitions;
    assumes = annotated.raw.assumes;
    guarantees = annotated.raw.guarantees;
    init_invariant_goals = annotated.init_invariant_goals;
  }

let source_nodes_by_name (source_program : Ast.program) : (Ast.ident * Ast.node) list =
  List.map (fun (node : Ast.node) -> (node.semantics.sem_nname, node)) source_program

let source_node_of_name ~(source_nodes : (Ast.ident * Ast.node) list) ~(node_name : Ast.ident) :
    (Ast.node, string) result =
  Result_utils.find_assoc
    ~missing:(fun name -> Printf.sprintf "Missing source AST node for IR node %s" name)
    node_name source_nodes

let analysis_context_of_source_node (source_node : Ast.node) : Ir.node_ir =
  let semantics = Ast.semantics_of_node source_node in
  {
    Ir.semantics =
      {
        sem_nname = semantics.sem_nname;
        sem_inputs = semantics.sem_inputs;
        sem_outputs = semantics.sem_outputs;
        sem_locals = semantics.sem_locals;
        sem_states = semantics.sem_states;
        sem_init_state = semantics.sem_init_state;
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout = Pre_k_collect.build_pre_k_infos source_node;
    summaries = [];
    init_invariant_goals = [];
  }

let build_node_analysis ~(automata : Automata_generation.node_builds)
    ~(program_transitions : Ir.transition list) (source_node : Ast.node) :
    (Product_build.analysis, string) result =
  let node = analysis_context_of_source_node source_node in
  let* build =
    Result_utils.find_assoc
      ~missing:(fun node_name -> Printf.sprintf "Missing automata build for IR node %s" node_name)
      node.semantics.sem_nname automata
  in
  Ok (Product_build.analyze_node ~build ~node ~program_transitions)

let build_analyses ~(automata : Automata_generation.node_builds)
    ~(source_nodes : (Ast.ident * Ast.node) list) :
    ((Ast.ident * Product_build.analysis) list, string) result =
  source_nodes
  |> List.map (fun (node_name, source_node) ->
         let analysis =
           build_node_analysis ~automata
             ~program_transitions:(program_transitions_of_ast_node source_node)
             source_node
         in
         Result.map (fun value -> (node_name, value)) analysis)
  |> Result_utils.all

let analysis_of_node ~(analyses : (Ast.ident * Product_build.analysis) list) (node : Ir.node_ir) :
    (Product_build.analysis, string) result =
  Result_utils.find_assoc
    ~missing:(fun node_name -> Printf.sprintf "Missing product analysis for IR node %s" node_name)
    node.semantics.sem_nname analyses

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
  let program_transitions = program_transitions_of_ast_node source_node in
  let raw_ir = build_raw_ir_node ~program_transitions node in
  let annotated_ir = annotate_raw_ir_node ~raw:raw_ir ~node in
  let verified_ir = verify_annotated_ir_node ~annotated:annotated_ir ~product_transitions:node.summaries in
  let rendered =
    Ir_render_product.render ~node_name:node.semantics.sem_nname ~analysis
  in
  let rendered_canonical =
    Ir_render_canonical.render ~node_name:node.semantics.sem_nname ~analysis ~node
  in
  let kernel_output =
    Proof_kernel_pass.compile_node
      {
        Proof_kernel_pass.node_name = node.semantics.sem_nname;
        source_node;
        node;
        analysis;
      }
  in
  let kernel_ir = kernel_output.normalized_ir in
  let exported_summary = kernel_output.exported_summary in
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
  let* analyses = build_analyses ~automata ~source_nodes in
  let node_results =
    program.nodes
    |> List.map (fun (node : Ir.node_ir) ->
           let* source_node =
             source_node_of_name ~source_nodes ~node_name:node.semantics.sem_nname
           in
           instrumentation_info_of_node ~source_node ~analyses node)
  in
  node_results |> Result_utils.all
  |> Result.map (List.fold_left merge_instrumentation_info Stage_info.empty_instrumentation_info)
