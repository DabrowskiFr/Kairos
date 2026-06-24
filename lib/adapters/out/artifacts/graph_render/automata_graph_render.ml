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

(** Public facade for Graphviz renderers of contract-verification automata. *)

open Core_syntax

type graph = {
  dot : string;
  labels : string;
}

let qualify_lines ~node_name text =
  text |> String.split_on_char '\n'
  |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
  |> String.concat "\n"

let render_ensures_automaton ~(node_name : ident)
    ~(analysis : Temporal_automata.node_data) : graph =
  let dot =
    Automata_graph_contract.emit_automaton_dot
      ~kind:Automata_graph_contract.Guarantee
      ~labels:analysis.guarantee_state_labels
      ~grouped:analysis.guarantee_grouped_edges
  in
  let labels =
    Automata_graph_contract.render_automaton_text ~prefix:"G"
      analysis.guarantee_state_labels analysis.guarantee_grouped_edges
    |> qualify_lines ~node_name
  in
  { dot; labels }

let render_require_automaton ~(node_name : ident)
    ~(analysis : Temporal_automata.node_data) : graph =
  let dot =
    Automata_graph_contract.emit_automaton_dot
      ~kind:Automata_graph_contract.Assume
      ~labels:analysis.assume_state_labels ~grouped:analysis.assume_grouped_edges
  in
  let labels =
    Automata_graph_contract.render_automaton_text ~prefix:"A"
      analysis.assume_state_labels analysis.assume_grouped_edges
    |> qualify_lines ~node_name
  in
  { dot; labels }

let render_product ~(node_name : ident)
    ~(analysis : Temporal_automata.node_data) : graph =
  let dot = Automata_graph_product.emit_product_dot analysis in
  let labels =
    Automata_graph_product.render_product_lines ~node_name analysis
    |> String.concat "\n"
  in
  { dot; labels }

let render_program_automaton ~(node_name : ident)
    ~(node : Verification_model.node_model) : graph =
  let dot = Automata_graph_program.emit_program_dot ~node_name node in
  let labels =
    Automata_graph_program.render_program_lines ~node_name node
    |> String.concat "\n"
  in
  { dot; labels }
