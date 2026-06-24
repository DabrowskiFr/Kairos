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
open Core_syntax_builders
open Automata_graph_dot
open Automata_graph_format

let render_program_lines ~(node_name : ident)
    (node : Verification_model.node_model) =
  let states =
    node.states
    |> List.map (fun st -> Printf.sprintf "[%s] P[%s]" node_name st)
  in
  let transitions =
    node.steps
    |> List.map (fun (t : Verification_model.program_step) ->
           let guard =
             match t.guard_expr with
             | None -> "⊤"
             | Some g -> g |> hexpr_of_expr |> pretty_plain_dot_formula
           in
           Printf.sprintf "[%s] P[%s -> %s] %s" node_name t.src_state
             t.dst_state guard)
  in
  states @ transitions

let prepare_program_graph (node : Verification_model.node_model) =
  let transitions_from_state state_name =
    List.filter
      (fun (step : Verification_model.program_step) ->
        String.equal step.src_state state_name)
      node.steps
  in
  let nodes =
    List.map
      (fun st ->
        let fill, border =
          if st = node.init_state then ("#dff3e4", "#2f7a4c")
          else ("#eef8f0", "#5e8f6b")
        in
        {
          node_id = Printf.sprintf "p_%s" (escape_dot_label st);
          node_label = `Plain st;
          node_fill = fill;
          node_border = border;
          node_fontcolor = Some border;
        })
      node.states
  in
  let edges =
    List.concat_map
      (fun st ->
        transitions_from_state st
        |> List.map (fun (t : Verification_model.program_step) ->
               let guard =
                 match t.guard_expr with
                 | None -> "⊤"
                 | Some g -> g |> hexpr_of_expr |> pretty_plain_dot_formula
               in
               {
                 edge_src = Printf.sprintf "p_%s" (escape_dot_label t.src_state);
                 edge_dst = Printf.sprintf "p_%s" (escape_dot_label t.dst_state);
                 edge_label = guard;
                 edge_color = "#5e8f6b";
                 edge_style = "solid";
               }))
      node.states
  in
  (nodes, edges)

let emit_program_dot ~(node_name : ident) (node : Verification_model.node_model) =
  let nodes, edges = prepare_program_graph node in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf "digraph ProgramAutomaton {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=t;\n";
  Buffer.add_string buf
    (Printf.sprintf "  label=\"%s program automaton\";\n" node_name);
  Buffer.add_string buf "  fontsize=18;\n";
  Buffer.add_string buf "  fontcolor=\"#275d38\";\n";
  Buffer.add_string buf
    "  node [shape=box,style=\"rounded,filled\",penwidth=1.6,fontname=\"Helvetica\",fontsize=12,margin=0.12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=12,penwidth=1.3,arrowsize=0.8,labeldistance=2.0,labelangle=35];\n";
  List.iter (emit_node buf) nodes;
  List.iter (emit_edge buf) edges;
  Buffer.add_string buf "}\n";
  Buffer.contents buf
