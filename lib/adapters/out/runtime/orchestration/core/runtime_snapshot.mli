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

(** Runtime-side snapshot types used by outgoing orchestration adapters.

    These types are intentionally kept in adapters/out because they represent
    technical assembly state (automata analyses, intermediate IR lists, stage
    infos) rather than application use-case DTOs.
*)

open Core_syntax

type ast_flow = {
  imports : string list;
  verification_model : Verification_model.program_model;
  automata_generation : Verification_model.program_model;
  automata : (ident * Automaton_types.automata_spec) list;
  summaries : Ir.node_ir list;
  instrumentation : Ir.node_ir list;
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
}
