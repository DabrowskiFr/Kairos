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

(** Product-step lookup helpers used by generated proof clauses. *)

val product_summary_of_step :
  ?projection:Core_syntax.historical Product_summary_projection.t ->
  node:Core_syntax.historical Ir.node_ir ->
  Proof_kernel_types.product_step_ir ->
  Core_syntax.historical Ir.product_step_summary option
