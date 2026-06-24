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

open Automata_graph_dot
open Automata_graph_format

type automaton_kind = Assume | Guarantee

let html_state_label ~state_prefix ~idx ~is_bad =
  if is_bad then Printf.sprintf "<I>%s</I><SUB>bad</SUB>" state_prefix
  else Printf.sprintf "<I>%s</I><SUB>%d</SUB>" state_prefix idx

let grouped_guard_rows grouped =
  let tbl = Hashtbl.create 16 in
  let next = ref 1 in
  grouped
  |> List.filter_map (fun (_src, guard, _dst) ->
         let formula = pretty_plain_dot_formula guard in
         if formula = "⊤" || Hashtbl.mem tbl formula then None
         else (
           let alias = phi_alias !next in
           incr next;
           Hashtbl.add tbl formula alias;
           Some (alias, formula)))

let render_automaton_text ~prefix labels grouped =
  let state_lines = render_automaton_lines ~prefix labels in
  let guard_lines =
    grouped_guard_rows grouped
    |> List.map (fun (alias, formula) ->
           let wrapped = wrap_formula_lines formula in
           match wrapped with
           | [] -> alias ^ " ::= "
           | first :: rest ->
               String.concat "\n"
                 ((Printf.sprintf "%s ::= %s" alias first)
                 :: List.map
                      (fun line ->
                        String.make (String.length alias + 5) ' ' ^ line)
                      rest))
  in
  String.concat "\n"
    (state_lines
    @
    if guard_lines = [] then []
    else [ ""; prefix ^ " transition guards:" ] @ guard_lines)

let prepare_automaton_graph ~kind ~labels ~grouped =
  let prefix, state_prefix, graph_name, node_fill, node_border, title_color,
      edge_color =
    match kind with
    | Assume ->
        ("a", "A", "AssumeAutomaton", "#e8f3ea", "#2f6b3b", "#2f6b3b",
         "#2f6b3b")
    | Guarantee ->
        ("g", "G", "GuaranteeAutomaton", "#f6eadf", "#8b5a2b", "#8b5a2b",
         "#8b5a2b")
  in
  let bad_fill = "#f6d7d7" in
  let bad_border = "#a53030" in
  let guard_rows = grouped_guard_rows grouped in
  let alias_tbl = Hashtbl.create 16 in
  List.iter (fun (alias, formula) -> Hashtbl.replace alias_tbl formula alias)
    guard_rows;
  let alias_of_guard s =
    match Hashtbl.find_opt alias_tbl s with Some a -> a | None -> s
  in
  let nodes =
    List.mapi
      (fun i lbl ->
        let is_bad = compact_display_string lbl = "false" in
        let fill =
          if is_bad then bad_fill else if i = 0 then "#d9e8ff" else node_fill
        in
        let border =
          if is_bad then bad_border
          else if i = 0 then "#3f6fb5"
          else node_border
        in
        {
          node_id = Printf.sprintf "%s%d" prefix i;
          node_label = `Html (html_state_label ~state_prefix ~idx:i ~is_bad);
          node_fill = fill;
          node_border = border;
          node_fontcolor = Some border;
        })
      labels
  in
  let edges =
    List.map
      (fun (src, guard, dst) ->
        let formula = pretty_plain_dot_formula guard in
        let dst_is_bad =
          match List.nth_opt labels dst with
          | Some lbl -> compact_display_string lbl = "false"
          | None -> false
        in
        {
          edge_src = Printf.sprintf "%s%d" prefix src;
          edge_dst = Printf.sprintf "%s%d" prefix dst;
          edge_label = alias_of_guard formula;
          edge_color = (if dst_is_bad then bad_border else edge_color);
          edge_style = "solid";
        })
      grouped
  in
  let anchor =
    match List.length labels with
    | 0 -> None
    | n -> Some (Printf.sprintf "%s%d" prefix (n - 1))
  in
  (graph_name, title_color, prefix, nodes, edges, guard_rows, anchor)

let emit_automaton_dot ~kind ~labels ~grouped =
  let graph_name, title_color, prefix, nodes, edges, guard_rows, anchor =
    prepare_automaton_graph ~kind ~labels ~grouped
  in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf (Printf.sprintf "digraph %s {\n" graph_name);
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=b;\n";
  Buffer.add_string buf "  labeljust=l;\n";
  Buffer.add_string buf "  fontsize=18;\n";
  Buffer.add_string buf (Printf.sprintf "  fontcolor=\"%s\";\n" title_color);
  Buffer.add_string buf
    "  node [shape=circle,style=filled,penwidth=1.6,fontname=\"Helvetica\",fontsize=12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=12,penwidth=1.3,arrowsize=0.8,labeldistance=2.0,labelangle=35];\n";
  List.iter (emit_node buf) nodes;
  List.iter (emit_edge buf) edges;
  emit_formula_legend buf ~legend_id:("legend_" ^ prefix)
    ~title:"Formula aliases" ~defs:guard_rows ~anchor;
  Buffer.add_string buf "}\n";
  Buffer.contents buf
