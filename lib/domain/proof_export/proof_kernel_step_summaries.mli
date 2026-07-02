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

(** Proof-step summary synthesis for proof-kernel export.

    This pass groups explicit product steps by canonical summary identity and
    attaches the relational clauses that must hold for each group. *)

val build_proof_step_summaries :
  node:Ir.node_ir ->
  reactive_program:Proof_kernel_types.reactive_program_ir ->
  product_steps:Proof_kernel_types.product_step_ir list ->
  temporal_layout:Ir.temporal_layout ->
  initial_product_state:Proof_kernel_types.product_state_ir ->
  symbolic_generated_clauses:
    Proof_kernel_types.relational_generated_clause_ir list ->
  Proof_kernel_types.proof_step_summary_ir list
