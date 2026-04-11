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
type node_input = {
  node_name : ident;
  source_node : Ast.node;
  node : Ir.node_ir;
  analysis : Temporal_automata.node_data;
}

type node_output = {
  normalized_ir : Proof_kernel_types.node_ir;
  exported_summary : Proof_kernel_types.exported_node_summary_ir;
}

val build_normalized_ir : node_input -> Proof_kernel_types.node_ir

val build_exported_summary :
  input:node_input ->
  normalized_ir:Proof_kernel_types.node_ir ->
  Proof_kernel_types.exported_node_summary_ir

val compile_node : node_input -> node_output
