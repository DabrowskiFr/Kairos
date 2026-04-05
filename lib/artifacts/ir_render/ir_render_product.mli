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

(** Product exploration renderers exposed through the artifacts layer. *)

type rendered = {
  guarantee_automaton_lines : string list;
  assume_automaton_lines : string list;
  guarantee_automaton_tex : string;
  assume_automaton_tex : string;
  product_tex : string;
  product_tex_explicit : string;
  product_lines : string list;
  obligations_lines : string list;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  product_dot_explicit : string;
}

val render :
  node_name:Ast.ident ->
  analysis:Product_analysis.analysis ->
  rendered

val render_guarantee_automaton :
  node_name:Ast.ident ->
  analysis:Product_analysis.analysis ->
  string * string

val render_program_automaton :
  node_name:Ast.ident ->
  node:Ir.node ->
  string * string
