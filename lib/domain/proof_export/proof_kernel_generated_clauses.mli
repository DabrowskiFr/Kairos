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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Bridge from product exploration to generated proof-kernel clauses. *)

(** Build the generated clauses for one node from its explicit product
    exploration and liveness predicate. *)
val build_generated_clauses :
  node:Ir.node_ir ->
  analysis:Temporal_automata.node_data ->
  initial_state:Proof_kernel_types.product_state_ir ->
  steps:Proof_kernel_types.product_step_ir list ->
  automaton_guard_fo:(Automaton_types.guard -> Core_syntax.hexpr) ->
  is_live_state:
    (analysis:Temporal_automata.node_data -> Product_types.product_state -> bool) ->
  Proof_kernel_types.generated_clause_ir list
