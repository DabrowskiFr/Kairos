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

module Verification_proof_ir =
  Kairos_verification_obligations.Verification_proof_ir

type ast_flow = {
  imports : string list;
  proof_case_program : Proof_case_program.t;
  automata : (ident * Automaton_types.automata_spec) list;
  product_nodes : Orchestration.product_node list;
  instrumentation : Core_syntax.history_free Ir.node_ir list;
  proof_plans : Verification_proof_ir.t list;
}

type flow_infos = {
  parse : Flow_info.parse_info option;
  automata_generation : Flow_info.automata_info option;
  summaries : Flow_info.summaries_info option;
  instrumentation : Flow_info.instrumentation_info option;
}

type pipeline_snapshot = {
  asts : ast_flow;
  infos : flow_infos;
  proof_encoding : Pipeline_config.proof_encoding;
  proof_optimizations : Pipeline_config.proof_optimizations;
}
