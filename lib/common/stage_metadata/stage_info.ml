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

type parse_error = { loc : Ast.loc option; message : string }

type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

type automata_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}

type contracts_info = {
  contract_origin_map : (int * Formula_origin.t option) list;
  warnings : string list;
}

type instrumentation_info = {
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
  exported_node_summaries : Proof_kernel_types.exported_node_summary_ir list;
  raw_ir_nodes : Proof_obligation_ir.raw_node list;
  annotated_ir_nodes : Proof_obligation_ir.annotated_node list;
  verified_ir_nodes : Proof_obligation_ir.verified_node list;
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

let empty_parse_info : parse_info =
  { source_path = None; text_hash = None; parse_errors = []; warnings = [] }

let empty_automata_info : automata_info =
  { residual_state_count = 0; residual_edge_count = 0; warnings = [] }

let empty_contracts_info : contracts_info = { contract_origin_map = []; warnings = [] }

let empty_instrumentation_info : instrumentation_info =
  {
    kernel_ir_nodes = [];
    exported_node_summaries = [];
    raw_ir_nodes = [];
    annotated_ir_nodes = [];
    verified_ir_nodes = [];
    kernel_pipeline_lines = [];
    warnings = [];
    guarantee_automaton_lines = [];
    assume_automaton_lines = [];
    product_lines = [];
    obligations_lines = [];
    prune_lines = [];
    guarantee_automaton_dot = "";
    assume_automaton_dot = "";
    product_dot = "";
  }
