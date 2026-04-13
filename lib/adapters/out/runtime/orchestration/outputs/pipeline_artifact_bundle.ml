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

open Core_syntax
open Ast
open Pretty

let ( let* ) = Result.bind
module Info_helpers = Instrumentation_info_helpers

type t = {
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
  exported_node_summaries : Proof_kernel_types.exported_node_summary_ir list;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  canonical_text : string;
  obligations_map_text_raw : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  canonical_dot : string;
}

type node_artifacts = {
  kernel_ir : Proof_kernel_types.node_ir;
  exported_summary : Proof_kernel_types.exported_node_summary_ir;
  require_graph : Automata_graph_render.graph;
  ensures_graph : Automata_graph_render.graph;
  product_graph : Automata_graph_render.graph;
}

let lower_guard_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list) ~(context : string)
    (guard : Core_syntax.hexpr) : (Core_syntax.hexpr, string) result =
  match Pre_k_lowering.lower_fo_formula_temporal_bindings ~temporal_bindings guard with
  | Some lowered -> Ok lowered
  | None ->
      Error
        (Printf.sprintf
           "Unable to lower temporal guard (%s) in product analysis for node %s: %s"
           context node_name (string_of_fo guard))

let lower_transition_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list) ~(context : string)
    ((src, guard, dst) : Automaton_types.transition) :
    (Automaton_types.transition, string) result =
  let* guard = lower_guard_for_kernel ~node_name ~temporal_bindings ~context guard in
  Ok (src, guard, dst)

let lower_product_step_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (step : Product_types.product_step) : (Product_types.product_step, string) result =
  let* prog_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"program guard"
      step.prog_guard
  in
  let* assume_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"assume guard"
      step.assume_guard
  in
  let* guarantee_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"guarantee guard"
      step.guarantee_guard
  in
  let* assume_edge =
    lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"assume edge"
      step.assume_edge
  in
  let* guarantee_edge =
    lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"guarantee edge"
      step.guarantee_edge
  in
  Ok { step with prog_guard; assume_guard; guarantee_guard; assume_edge; guarantee_edge }

let lower_analysis_for_kernel ~(node : Ir.node_ir)
    ~(analysis : Temporal_automata.node_data) :
    (Temporal_automata.node_data, string) result =
  let temporal_bindings = Ir_formula.temporal_bindings_of_node node in
  let node_name = node.semantics.sem_nname in
  let* assume_grouped_edges =
    analysis.assume_grouped_edges
    |> List.map
         (lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"assume automaton")
    |> Result_utils.all
  in
  let* guarantee_grouped_edges =
    analysis.guarantee_grouped_edges
    |> List.map
         (lower_transition_for_kernel ~node_name ~temporal_bindings
            ~context:"guarantee automaton")
    |> Result_utils.all
  in
  let* steps =
    analysis.exploration.steps
    |> List.map (lower_product_step_for_kernel ~node_name ~temporal_bindings)
    |> Result_utils.all
  in
  Ok
    {
      analysis with
      assume_grouped_edges;
      guarantee_grouped_edges;
      exploration = { analysis.exploration with steps };
    }

let build_node_artifacts ~(source_node : Ast.node)
    ~(analysis : Temporal_automata.node_data) (node : Ir.node_ir) :
    (node_artifacts, string) result =
  let* analysis_for_kernel = lower_analysis_for_kernel ~node ~analysis in
  let kernel_output =
    Proof_kernel_pass.compile_node
      {
        Proof_kernel_pass.node_name = node.semantics.sem_nname;
        source_node;
        node;
        analysis = analysis_for_kernel;
      }
  in
  let require_graph =
    Automata_graph_render.render_require_automaton ~node_name:node.semantics.sem_nname
      ~analysis
  in
  let ensures_graph =
    Automata_graph_render.render_ensures_automaton ~node_name:node.semantics.sem_nname
      ~analysis
  in
  let product_graph =
    Automata_graph_render.render_product ~node_name:node.semantics.sem_nname ~analysis
  in
  Ok
    {
      kernel_ir = kernel_output.normalized_ir;
      exported_summary = kernel_output.exported_summary;
      require_graph;
      ensures_graph;
      product_graph;
    }

let first_non_empty (xs : string list) : string =
  match List.find_opt (fun s -> String.trim s <> "") xs with Some s -> s | None -> ""

let join_non_empty (xs : string list) : string =
  xs
  |> List.filter (fun s -> String.trim s <> "")
  |> String.concat "\n\n"

let build ~(asts : Pipeline_types.ast_flow) : (t, string) result =
  let source_nodes_model = Info_helpers.source_nodes_by_name asts.verification_model in
  let source_nodes_ast =
    List.map
      (fun (node : Ast.node) -> (node.semantics.sem_nname, node))
      asts.automata_generation
  in
  let source_ast_node_of_name (node_name : ident) : (Ast.node, string) result =
    match List.assoc_opt node_name source_nodes_ast with
    | Some node -> Ok node
    | None -> Error (Printf.sprintf "Missing source AST node for IR node %s" node_name)
  in
  let* analyses = Info_helpers.build_analyses ~automata:asts.automata ~source_nodes:source_nodes_model in
  let* node_artifacts =
    asts.instrumentation
    |> List.map (fun (node : Ir.node_ir) ->
           let* source_node = source_ast_node_of_name node.semantics.sem_nname in
           let* analysis = Info_helpers.analysis_of_node ~analyses node in
           build_node_artifacts ~source_node ~analysis node)
    |> Result_utils.all
  in
  let kernel_ir_nodes = List.map (fun (n : node_artifacts) -> n.kernel_ir) node_artifacts in
  let exported_node_summaries =
    List.map (fun (n : node_artifacts) -> n.exported_summary) node_artifacts
  in
  let guarantee_automaton_text =
    join_non_empty
      (List.map (fun (n : node_artifacts) -> n.ensures_graph.labels) node_artifacts)
  in
  let assume_automaton_text =
    join_non_empty
      (List.map (fun (n : node_artifacts) -> n.require_graph.labels) node_artifacts)
  in
  let product_text =
    join_non_empty
      (List.map (fun (n : node_artifacts) -> n.product_graph.labels) node_artifacts)
  in
  let guarantee_automaton_dot =
    first_non_empty
      (List.map (fun (n : node_artifacts) -> n.ensures_graph.dot) node_artifacts)
  in
  let assume_automaton_dot =
    first_non_empty
      (List.map (fun (n : node_artifacts) -> n.require_graph.dot) node_artifacts)
  in
  let product_dot =
    first_non_empty
      (List.map (fun (n : node_artifacts) -> n.product_graph.dot) node_artifacts)
  in
  Ok
    {
      kernel_ir_nodes;
      exported_node_summaries;
      guarantee_automaton_text;
      assume_automaton_text;
      product_text;
      canonical_text = "";
      obligations_map_text_raw = "";
      guarantee_automaton_dot;
      assume_automaton_dot;
      product_dot;
      canonical_dot = "";
    }
