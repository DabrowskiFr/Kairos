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
open Pretty
open Automata_graph_dot
open Automata_graph_format

module PT = Product_types

let string_of_state (s : PT.product_state) : string =
  Printf.sprintf "(%s, A%d, G%d)" s.prog_state
    s.assume_state_index s.guarantee_state_index

let detailed_state (_analysis : Temporal_automata.node_data)
    (state : PT.product_state) =
  string_of_state state

let render_product_lines ~(node_name : ident)
    (analysis : Temporal_automata.node_data) =
  let states =
    PT.states analysis.exploration
    |> List.map (fun st ->
           Printf.sprintf "[%s] state %s" node_name
             (detailed_state analysis st))
  in
  let steps =
    analysis.exploration.prefixes
    |> List.concat_map (fun (prefix : PT.product_prefix) ->
           let src = PT.prefix_source prefix in
           prefix.guarantee_successors
           |> List.map
                (fun
                  (guarantee_successor :
                    PT.monitor_successor)
                ->
                  let dst =
                    PT.successor_destination prefix
                      guarantee_successor
                  in
                  Printf.sprintf
                    "[%s] %s -- P:%s / A[%s]:%s / G[%s]:%s --> %s"
                    node_name
                    (detailed_state analysis src)
                    (string_of_fo
                       (PT.program_guard prefix))
                    (Printf.sprintf "%d->%d"
                       src.assume_state_index
                       dst.assume_state_index)
                    (string_of_fo
                       prefix.assume_successor.guard)
                    (Printf.sprintf "%d->%d"
                       src.guarantee_state_index
                       dst.guarantee_state_index)
                    (string_of_fo
                       guarantee_successor.guard)
                    (detailed_state analysis dst)))
  in
  states @ steps

let node_id_of_state (s : PT.product_state) : string =
  Printf.sprintf "n_%s_a%d_g%d" s.prog_state
    s.assume_state_index s.guarantee_state_index

let product_state_index_map (states : PT.product_state list) =
  let tbl = Hashtbl.create 32 in
  List.iteri (fun i st -> Hashtbl.replace tbl st i) states;
  tbl

let pretty_product_state (_analysis : Temporal_automata.node_data)
    (state : PT.product_state) : string =
  Printf.sprintf "(%s, A%s, G%s)" state.prog_state
    (subscript_digits state.assume_state_index)
    (subscript_digits state.guarantee_state_index)

let product_edge_color = "#222222"

let product_node_fill (s : PT.product_state)
    ~(analysis : Temporal_automata.node_data) =
  if PT.compare_state s analysis.exploration.initial_state = 0 then
    ("#d9e8ff", "#3f6fb5")
  else ("white", "#6b7280")

type merged_product_edge = {
  src : PT.product_state;
  dst : PT.product_state;
  prog_guard : Core_syntax.historical Core_syntax.hexpr;
  assume_guard : Core_syntax.historical Core_syntax.hexpr;
  guarantee_guard : Core_syntax.historical Core_syntax.hexpr;
}

type product_edge_visual = {
  color : string;
  style : string;
}

let merge_product_steps_for_dot
    (analysis : Temporal_automata.node_data) : merged_product_edge list =
  let tbl = Hashtbl.create 64 in
  List.iter
    (fun (prefix : PT.product_prefix) ->
      let src = PT.prefix_source prefix in
      let prog_guard = PT.program_guard prefix in
      List.iter
        (fun
          (guarantee_successor : PT.monitor_successor)
        ->
          let dst =
            PT.successor_destination prefix
              guarantee_successor
          in
          let key =
            ( src,
              dst,
              prefix.assume_successor.guard,
              guarantee_successor.guard )
          in
          match Hashtbl.find_opt tbl key with
          | None ->
              Hashtbl.add tbl key
                {
                  src;
                  dst;
                  prog_guard;
                  assume_guard =
                    prefix.assume_successor.guard;
                  guarantee_guard =
                    guarantee_successor.guard;
                }
          | Some merged ->
              Hashtbl.replace tbl key
                {
                  merged with
                  prog_guard =
                    mk_hor merged.prog_guard prog_guard;
                })
        prefix.guarantee_successors)
    analysis.exploration.prefixes;
  Hashtbl.fold (fun _ step acc -> step :: acc) tbl []
  |> List.sort (fun a b ->
         compare
           ( string_of_state a.src,
             string_of_state a.dst,
             pretty_product_formula a.prog_guard )
           ( string_of_state b.src,
             string_of_state b.dst,
             pretty_product_formula b.prog_guard ))

let product_edge_visual : product_edge_visual =
  { color = product_edge_color; style = "solid" }

let prepare_product_graph (analysis : Temporal_automata.node_data) =
  let states = PT.states analysis.exploration in
  let state_indices = product_state_index_map states in
  let nodes =
    List.map
      (fun st ->
        let fill, border = product_node_fill st ~analysis in
        let idx = Hashtbl.find state_indices st in
        let label =
          Printf.sprintf "P%s\n%s" (subscript_digits idx)
            (pretty_product_state analysis st)
        in
        {
          node_id = node_id_of_state st;
          node_label = `Plain label;
          node_fill = fill;
          node_border = border;
          node_fontcolor = None;
        })
      states
  in
  let detail_tbl = Hashtbl.create 64 in
  let detail_rev = ref [] in
  let next_alias = ref 1 in
  let alias_of_detail detail =
    match Hashtbl.find_opt detail_tbl detail with
    | Some alias -> alias
    | None ->
        let alias = tau_alias !next_alias in
        incr next_alias;
        Hashtbl.add detail_tbl detail alias;
        detail_rev := (alias, detail) :: !detail_rev;
        alias
  in
  let seen = Hashtbl.create 64 in
  let edges =
    merge_product_steps_for_dot analysis
    |> List.filter_map (fun (step : merged_product_edge) ->
           let visual = product_edge_visual in
           let label =
             alias_of_detail
               (Printf.sprintf "P: %s\nA: %s\nG: %s"
                  (pretty_plain_dot_formula step.prog_guard)
                  (pretty_plain_dot_formula step.assume_guard)
                  (pretty_plain_dot_formula step.guarantee_guard))
           in
           let key =
             Printf.sprintf "%s|%s|%s|%s|%s" (node_id_of_state step.src)
               (node_id_of_state step.dst) visual.color visual.style label
           in
           if Hashtbl.mem seen key then None
           else (
             Hashtbl.add seen key ();
             Some
               {
                 edge_src = node_id_of_state step.src;
                 edge_dst = node_id_of_state step.dst;
                 edge_label = label;
                 edge_color = visual.color;
                 edge_style = visual.style;
               }))
  in
  let anchor =
    match List.rev states with
    | last :: _ -> Some (node_id_of_state last)
    | [] -> None
  in
  (nodes, edges, List.rev !detail_rev, anchor)

let emit_product_dot (analysis : Temporal_automata.node_data) =
  let nodes, edges, transition_defs, anchor = prepare_product_graph analysis in
  let buf = Buffer.create 2048 in
  Buffer.add_string buf "digraph Product {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=b;\n";
  Buffer.add_string buf "  labeljust=l;\n";
  Buffer.add_string buf "  fontsize=10;\n";
  Buffer.add_string buf "  fontname=\"Helvetica\";\n";
  Buffer.add_string buf
    "  node [shape=box,style=\"rounded,filled\",penwidth=1.4,fontname=\"Helvetica\",fontsize=11,margin=0.12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=11,penwidth=1.25,arrowsize=0.75];\n";
  List.iter (emit_node buf) nodes;
  List.iter (emit_edge buf) edges;
  let category_rows =
    let b = Buffer.create 256 in
    Buffer.add_string b
      (Printf.sprintf
         "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">product step</FONT></TD></TR>\n"
         product_edge_color);
    Buffer.contents b
  in
  Option.iter
    (fun anchor_id ->
      let rows_buf = Buffer.create 512 in
      Buffer.add_string rows_buf category_rows;
      add_formula_legend_rows_html rows_buf ~title:"Transition formulas"
        ~defs:transition_defs;
      add_sink_legend_block_html buf ~legend_id:"legend_product"
        ~title:"Edge categories" ~rows_html:(Buffer.contents rows_buf)
        ~anchor_id)
    anchor;
  Buffer.add_string buf "}\n";
  Buffer.contents buf
