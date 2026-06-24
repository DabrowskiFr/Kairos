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

(** Low-level Graphviz DOT emission helpers for automata graphs. *)

val escape_dot_label : string -> string
val escape_html_label : string -> string
val html_of_multiline_formula : string -> string

val add_formula_legend_rows_html :
  Buffer.t -> title:string -> defs:(string * string) list -> unit

val add_sink_legend_block_html :
  Buffer.t ->
  legend_id:string ->
  title:string ->
  rows_html:string ->
  anchor_id:string ->
  unit

val add_labeled_edge :
  Buffer.t ->
  src_id:string ->
  dst_id:string ->
  label:string ->
  color:string ->
  style:string ->
  unit

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

val emit_node : Buffer.t -> ready_node -> unit
val emit_edge : Buffer.t -> ready_edge -> unit

val emit_formula_legend :
  Buffer.t ->
  legend_id:string ->
  title:string ->
  defs:(string * string) list ->
  anchor:string option ->
  unit
