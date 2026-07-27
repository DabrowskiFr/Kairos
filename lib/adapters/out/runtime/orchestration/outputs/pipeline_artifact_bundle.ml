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

type t = {
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
}

type node_artifacts = {
  require_graph : Automata_graph_render.graph;
  ensures_graph : Automata_graph_render.graph;
  product_graph : Automata_graph_render.graph;
}

let build_node_artifacts (reference : Orchestration.reference_node) :
    node_artifacts =
  let node_name = reference.reference_model.node_name in
  let analysis = reference.analysis in
  let require_graph =
    Automata_graph_render.render_require_automaton ~node_name ~analysis
  in
  let ensures_graph =
    Automata_graph_render.render_ensures_automaton ~node_name ~analysis
  in
  let product_graph =
    Automata_graph_render.render_product ~node_name ~analysis
  in
  { require_graph; ensures_graph; product_graph }

let build ~(asts : Runtime_snapshot.ast_flow) : t =
  let node_artifacts =
    List.map build_node_artifacts asts.reference_nodes
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
  {
    guarantee_automaton_text;
    assume_automaton_text;
    product_text;
    guarantee_automaton_dot;
    assume_automaton_dot;
    product_dot;
  }
