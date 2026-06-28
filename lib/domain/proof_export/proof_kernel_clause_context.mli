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

(** Bridge between proof-export product records and neutral kernel-clause
    contexts.

    This module is deliberately about product/context representation only. It
    does not construct, classify, filter, or lower kernel clauses. *)

val product_state_to_kernel :
  Proof_kernel_types.product_state_ir ->
  Kernel_clause_projection.product_state_anchor

val product_state_of_kernel :
  Kernel_clause_projection.product_state_anchor ->
  Proof_kernel_types.product_state_ir

val product_step_to_kernel :
  Proof_kernel_types.product_step_ir ->
  Kernel_clause_projection.product_step

val product_step_of_kernel :
  Kernel_clause_projection.product_step ->
  Proof_kernel_types.product_step_ir

val product_state_to_product_types :
  Kernel_clause_projection.product_state_anchor -> Product_types.product_state

val same_product_step :
  Kernel_clause_projection.product_step ->
  Proof_kernel_types.product_step_ir ->
  bool
