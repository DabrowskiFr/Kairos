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

(* {1 Per‑pass Metadata} *)

(* Parser error payload. *)
type parse_error = { loc : Ast.loc option; message : string }

(* Parsing metadata reported by the frontend. *)
type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

(* Metadata produced by the monitor generation pass. *)
type automata_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}

(* Metadata produced by the contracts pass. *)
type contracts_info = {
  contract_origin_map : (int * Ast.origin option) list;
  warnings : string list;
}

(* Metadata produced by the monitor instrumentation pass. *)
type instrumentation_info = {
  state_ctors : string list;
  atom_count : int;
  kernel_ir_nodes : Product_kernel_ir.node_ir list;
  (** Pass 3 output: raw IR nodes (no Hoare triples). *)
  raw_ir_nodes : Kairos_ir.raw_node list;
  (** Pass 4 output: annotated IR nodes (Hoare triples added, pre_k references still present). *)
  annotated_ir_nodes : Kairos_ir.annotated_node list;
  (** Pass 5 output: verified IR nodes (history eliminated, ready for Why3). *)
  verified_ir_nodes : Kairos_ir.verified_node list;
  kernel_pipeline_lines : string list;
  warnings : string list;
  guarantee_automaton_lines : string list;
  assume_automaton_lines : string list;
  product_lines : string list;
  obligations_lines : string list;
  prune_lines : string list;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
}

(* Default (empty) parse metadata. *)
val empty_parse_info : parse_info

(* Default (empty) monitor generation metadata. *)
val empty_automata_info : automata_info

(* Default (empty) contracts metadata. *)
val empty_contracts_info : contracts_info

(* Default (empty) monitor injection metadata. *)
val empty_instrumentation_info : instrumentation_info
