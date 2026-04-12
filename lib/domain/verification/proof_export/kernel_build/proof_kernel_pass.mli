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

(** Proof-kernel export pass interface.

    This module converts one canonical IR node plus product analysis into:
    - normalized proof-kernel IR;
    - exported summary payload for [.kobj]. *)

open Core_syntax

(** Input bundle required to compile one node into proof-kernel artifacts. *)
type node_input = {
  node_name : ident;
  source_node : Ast.node;
  node : Ir.node_ir;
  analysis : Temporal_automata.node_data;
}

(** Output bundle produced for one compiled node. *)
type node_output = {
  normalized_ir : Proof_kernel_types.node_ir;
  exported_summary : Proof_kernel_types.exported_node_summary_ir;
}

(** Build normalized proof-kernel IR for one node. *)
val build_normalized_ir : node_input -> Proof_kernel_types.node_ir

(** Build exported node summary from node input and normalized IR. *)
val build_exported_summary :
  input:node_input ->
  normalized_ir:Proof_kernel_types.node_ir ->
  Proof_kernel_types.exported_node_summary_ir

(** Compile one node end-to-end into normalized IR + exported summary. *)
val compile_node : node_input -> node_output
