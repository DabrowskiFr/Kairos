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

let escape_dot_label (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let escape_html_label (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let html_of_multiline_formula (s : string) : string =
  let escaped = escape_html_label s in
  let b = Buffer.create (String.length escaped) in
  String.iter
    (function
      | '\n' -> Buffer.add_string b "<BR ALIGN=\"LEFT\"/>"
      | c -> Buffer.add_char b c)
    escaped;
  Buffer.contents b

let add_formula_legend_rows_html buf ~title ~defs =
  if defs <> [] then (
    Buffer.add_string buf
      (Printf.sprintf
         "      <TR><TD COLSPAN=\"2\" ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\"><B>%s</B></FONT></TD></TR>\n"
         (escape_html_label title));
    List.iter
      (fun (alias, formula) ->
        Buffer.add_string buf
          (Printf.sprintf
             "      <TR><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">%s</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">%s</FONT></TD></TR>\n"
             (escape_html_label alias) (html_of_multiline_formula formula)))
      defs)

let add_sink_legend_block_html buf ~legend_id ~title ~rows_html ~anchor_id =
  Buffer.add_string buf "  subgraph cluster_legend_sink {\n";
  Buffer.add_string buf "    rank=sink;\n";
  Buffer.add_string buf "    color=\"transparent\";\n";
  Buffer.add_string buf "    margin=0;\n";
  Buffer.add_string buf
    (Printf.sprintf "    %s [shape=plaintext,margin=0.1,label=<\n" legend_id);
  Buffer.add_string buf "      <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n";
  Buffer.add_string buf
    (Printf.sprintf
       "        <TR><TD COLSPAN=\"2\" ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\"><B>%s</B></FONT></TD></TR>\n"
       (escape_html_label title));
  Buffer.add_string buf rows_html;
  Buffer.add_string buf "      </TABLE>>];\n";
  Buffer.add_string buf "  }\n";
  Buffer.add_string buf
    (Printf.sprintf "  %s -> %s [style=invis,weight=0];\n" anchor_id legend_id)

let add_labeled_edge buf ~src_id ~dst_id ~label ~color ~style =
  Buffer.add_string buf
    (Printf.sprintf "  %s -> %s [label=\"%s\",color=\"%s\",fontcolor=\"%s\",style=\"%s\"];\n"
       src_id dst_id (escape_dot_label label) color color style)

type ready_node = {
  node_id : string;
  node_label : [ `Plain of string | `Html of string ];
  node_fill : string;
  node_border : string;
  node_fontcolor : string option;
}

type ready_edge = {
  edge_src : string;
  edge_dst : string;
  edge_label : string;
  edge_color : string;
  edge_style : string;
}

let emit_node buf (n : ready_node) =
  let label_attr = match n.node_label with
    | `Plain s -> Printf.sprintf "label=\"%s\"" (escape_dot_label s)
    | `Html s  -> Printf.sprintf "label=<%s>" s
  in
  let fontcolor_attr = match n.node_fontcolor with
    | None   -> ""
    | Some c -> Printf.sprintf ",fontcolor=\"%s\"" c
  in
  Buffer.add_string buf
    (Printf.sprintf "  %s [fillcolor=\"%s\",color=\"%s\"%s,%s];\n"
       n.node_id n.node_fill n.node_border fontcolor_attr label_attr)

let emit_edge buf (e : ready_edge) =
  if e.edge_label = "" then
    Buffer.add_string buf
      (Printf.sprintf "  %s -> %s [color=\"%s\",style=\"%s\"];\n"
         e.edge_src e.edge_dst e.edge_color e.edge_style)
  else
    add_labeled_edge buf ~src_id:e.edge_src ~dst_id:e.edge_dst
      ~label:e.edge_label ~color:e.edge_color ~style:e.edge_style

let emit_formula_legend buf ~legend_id ~title ~defs ~anchor =
  if defs <> [] then
    Option.iter (fun anchor_id ->
      let rows_buf = Buffer.create 256 in
      add_formula_legend_rows_html rows_buf ~title ~defs;
      add_sink_legend_block_html buf ~legend_id ~title
        ~rows_html:(Buffer.contents rows_buf) ~anchor_id)
    anchor
