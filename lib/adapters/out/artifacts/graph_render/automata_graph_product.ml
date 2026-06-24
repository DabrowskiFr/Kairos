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
  Printf.sprintf "(%s, A%d, G%d)" s.prog_state s.assume_state
    s.guarantee_state

let string_of_step_class = function
  | PT.Safe -> "safe"
  | PT.Bad_assumption -> "bad_A"
  | PT.Bad_guarantee -> "bad_G"

let string_of_edge ((src, _guard, dst) : PT.automaton_edge) : string =
  Printf.sprintf "%d->%d" src dst

let render_product_lines ~(node_name : ident)
    (analysis : Temporal_automata.node_data) =
  let states =
    analysis.exploration.states
    |> List.map (fun st ->
           Printf.sprintf "[%s] state %s" node_name (string_of_state st))
  in
  let steps =
    analysis.exploration.steps
    |> List.map (fun (step : PT.product_step) ->
           Printf.sprintf
             "[%s] %s -- P:%s / A[%s]:%s / G[%s]:%s --> %s [%s]"
             node_name (string_of_state step.src) (string_of_fo step.prog_guard)
             (string_of_edge step.assume_edge) (string_of_fo step.assume_guard)
             (string_of_edge step.guarantee_edge)
             (string_of_fo step.guarantee_guard)
             (string_of_state step.dst)
             (string_of_step_class step.step_class))
  in
  states @ steps

let node_id_of_state (s : PT.product_state) : string =
  Printf.sprintf "n_%s_a%d_g%d" s.prog_state s.assume_state s.guarantee_state

let product_state_index_map (states : PT.product_state list) =
  let tbl = Hashtbl.create 32 in
  List.iteri (fun i st -> Hashtbl.replace tbl st i) states;
  tbl

let pretty_product_state (s : PT.product_state)
    ~(analysis : Temporal_automata.node_data) : string =
  Printf.sprintf "(%s, %s, %s)" s.prog_state
    (pretty_aut_state ~prefix:"A" ~idx:s.assume_state
       ~bad_idx:analysis.assume_bad_idx)
    (pretty_aut_state ~prefix:"G" ~idx:s.guarantee_state
       ~bad_idx:analysis.guarantee_bad_idx)

let clr_live_to_live = "#222222"
let clr_to_gbad = "#c0392b"
let clr_to_abad = "#c78a2c"
let clr_from_bad = "#b8b8b8"

let product_node_fill (s : PT.product_state)
    ~(analysis : Temporal_automata.node_data) =
  if PT.compare_state s analysis.exploration.initial_state = 0 then
    ("#d9e8ff", "#3f6fb5")
  else if
    analysis.guarantee_bad_idx >= 0
    && s.guarantee_state = analysis.guarantee_bad_idx
  then ("#f6d7d7", "#a53030")
  else if
    analysis.assume_bad_idx >= 0 && s.assume_state = analysis.assume_bad_idx
  then ("#f9ead7", "#b26a1f")
  else ("white", "#6b7280")

type merged_product_edge = {
  src : PT.product_state;
  dst : PT.product_state;
  step_class : PT.step_class;
  prog_guard : Core_syntax.hexpr;
  assume_guard : Core_syntax.hexpr;
  guarantee_guard : Core_syntax.hexpr;
}

type product_edge_visual = {
  color : string;
  style : string;
  category : string;
}

let merge_product_steps_for_dot
    (analysis : Temporal_automata.node_data) : merged_product_edge list =
  let tbl = Hashtbl.create 64 in
  let key_of_step (step : PT.product_step) =
    ( step.src,
      step.dst,
      step.step_class,
      step.assume_edge,
      step.guarantee_edge,
      step.assume_guard,
      step.guarantee_guard )
  in
  List.iter
    (fun (step : PT.product_step) ->
      let key = key_of_step step in
      match Hashtbl.find_opt tbl key with
      | None ->
          Hashtbl.add tbl key
            {
              src = step.src;
              dst = step.dst;
              step_class = step.step_class;
              prog_guard = step.prog_guard;
              assume_guard = step.assume_guard;
              guarantee_guard = step.guarantee_guard;
            }
      | Some merged ->
          Hashtbl.replace tbl key
            {
              merged with
              prog_guard = mk_hor merged.prog_guard step.prog_guard;
            })
    analysis.exploration.steps;
  Hashtbl.fold (fun _ step acc -> step :: acc) tbl []
  |> List.sort (fun a b ->
         compare
           ( string_of_state a.src,
             string_of_state a.dst,
             string_of_step_class a.step_class,
             pretty_product_formula a.prog_guard )
           ( string_of_state b.src,
             string_of_state b.dst,
             string_of_step_class b.step_class,
             pretty_product_formula b.prog_guard ))

let product_edge_visual ~(analysis : Temporal_automata.node_data)
    (step : merged_product_edge) : product_edge_visual =
  let src_live =
    step.src.assume_state <> analysis.assume_bad_idx
    && step.src.guarantee_state <> analysis.guarantee_bad_idx
  in
  let dst_assume_bad =
    analysis.assume_bad_idx >= 0
    && step.dst.assume_state = analysis.assume_bad_idx
  in
  let dst_guarantee_bad =
    analysis.guarantee_bad_idx >= 0
    && step.dst.guarantee_state = analysis.guarantee_bad_idx
  in
  if not src_live then
    { color = clr_from_bad; style = "dashed"; category = "from bad state" }
  else if dst_assume_bad then
    { color = clr_to_abad; style = "dashed"; category = "to A_bad" }
  else if dst_guarantee_bad then
    { color = clr_to_gbad; style = "solid"; category = "to G_bad" }
  else { color = clr_live_to_live; style = "solid"; category = "live to live" }

let prepare_product_graph (analysis : Temporal_automata.node_data) =
  let state_indices = product_state_index_map analysis.exploration.states in
  let is_live (st : PT.product_state) =
    st.assume_state <> analysis.assume_bad_idx
    && st.guarantee_state <> analysis.guarantee_bad_idx
  in
  let nodes =
    List.map
      (fun st ->
        let fill, border = product_node_fill st ~analysis in
        let idx = Hashtbl.find state_indices st in
        let label =
          Printf.sprintf "P%s\n%s" (subscript_digits idx)
            (pretty_product_state st ~analysis)
        in
        {
          node_id = node_id_of_state st;
          node_label = `Plain label;
          node_fill = fill;
          node_border = border;
          node_fontcolor = None;
        })
      analysis.exploration.states
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
           let visual = product_edge_visual ~analysis step in
           let label =
             if
               is_live step.src
               && (analysis.assume_bad_idx < 0
                  || step.dst.assume_state <> analysis.assume_bad_idx)
             then
               alias_of_detail
                 (Printf.sprintf "P: %s\nA: %s\nG: %s"
                    (pretty_plain_dot_formula step.prog_guard)
                    (pretty_plain_dot_formula step.assume_guard)
                    (pretty_plain_dot_formula step.guarantee_guard))
             else ""
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
    match List.rev analysis.exploration.states with
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
         "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">live to live</FONT></TD></TR>\n"
         clr_live_to_live);
    Buffer.add_string b
      (Printf.sprintf
         "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to G_bad</FONT></TD></TR>\n"
         clr_to_gbad);
    Buffer.add_string b
      (Printf.sprintf
         "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to A_bad</FONT></TD></TR>\n"
         clr_to_abad);
    Buffer.add_string b
      (Printf.sprintf
         "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">from bad state</FONT></TD></TR>\n"
         clr_from_bad);
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
