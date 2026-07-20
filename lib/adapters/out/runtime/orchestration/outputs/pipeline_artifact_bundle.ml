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

let build_node_artifacts ~(source_node : Verification_model.node_model)
    ~(analysis : Temporal_automata.node_data) (node : Ir.node_ir) :
    (node_artifacts, string) result =
  let kernel_output =
    Proof_kernel_pass.compile_node
      {
        Proof_kernel_pass.node_name = node.semantics.sem_nname;
        source_node;
        node;
        analysis;
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

let build ~(asts : Runtime_snapshot.ast_flow) : (t, string) result =
  let source_nodes_model = Info_helpers.source_nodes_by_name asts.reference_program in
  let source_node_of_name (node_name : ident) : (Verification_model.node_model, string) result =
    match List.assoc_opt node_name source_nodes_model with
    | Some node -> Ok node
    | None -> Error (Printf.sprintf "Missing source model node for IR node %s" node_name)
  in
  let* analyses = Info_helpers.build_analyses ~automata:asts.automata ~source_nodes:source_nodes_model in
  let* node_artifacts =
    asts.proof_instrumentation
    |> List.map (fun (node : Ir.node_ir) ->
           let* source_node = source_node_of_name node.semantics.sem_nname in
           let* analysis = Info_helpers.analysis_of_node ~analyses node in
           build_node_artifacts ~source_node ~analysis node)
    |> Result_utils.all
  in
  let kernel_ir_nodes = List.map (fun (n : node_artifacts) -> n.kernel_ir) node_artifacts in
  let exported_node_summaries =
    List.map (fun (n : node_artifacts) -> n.exported_summary) node_artifacts
  in
  let guarantee_automaton_text =
    Pipeline_artifact_bundle_text.join_non_empty
      (List.map (fun (n : node_artifacts) -> n.ensures_graph.labels) node_artifacts)
  in
  let assume_automaton_text =
    Pipeline_artifact_bundle_text.join_non_empty
      (List.map (fun (n : node_artifacts) -> n.require_graph.labels) node_artifacts)
  in
  let product_text =
    Pipeline_artifact_bundle_text.join_non_empty
      (List.map (fun (n : node_artifacts) -> n.product_graph.labels) node_artifacts)
  in
  let guarantee_automaton_dot =
    Pipeline_artifact_bundle_text.first_non_empty
      (List.map (fun (n : node_artifacts) -> n.ensures_graph.dot) node_artifacts)
  in
  let assume_automaton_dot =
    Pipeline_artifact_bundle_text.first_non_empty
      (List.map (fun (n : node_artifacts) -> n.require_graph.dot) node_artifacts)
  in
  let product_dot =
    Pipeline_artifact_bundle_text.first_non_empty
      (List.map (fun (n : node_artifacts) -> n.product_graph.dot) node_artifacts)
  in
  Ok
    {
      kernel_ir_nodes;
      exported_node_summaries;
      guarantee_automaton_text;
      assume_automaton_text;
      product_text;
      canonical_text =
        Pipeline_artifact_bundle_text.render_canonical exported_node_summaries;
      obligations_map_text_raw =
        Pipeline_artifact_bundle_text.render_obligations_map exported_node_summaries;
      guarantee_automaton_dot;
      assume_automaton_dot;
      product_dot;
      canonical_dot = "";
    }
