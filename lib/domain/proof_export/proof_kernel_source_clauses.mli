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

(** Construction of generated clauses from canonical summaries and product data.

    This module derives source-level, phase and safety clauses before
    relational lowering. *)

(** Source-summary clauses derived from canonical product summaries. *)

val build_source_summary_clauses :
  node:Ir.node_ir ->
  analysis:Temporal_automata.node_data ->
  steps:Proof_kernel_types.product_step_ir list ->
  automaton_guard_fo:'a ->
  Proof_kernel_types.generated_clause_ir list
