(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Canonical Stage 1 proof-obligation data before derived views and backends.

    It does not own JSON export, backend contracts, diagnostics, solver
    scheduling, or proof artifacts. *)

type stage1 = {
  product_summaries :
    Core_syntax.historical Product_summary_projection.t;
  clauses : Kernel_clause_projection.classified_clause list;
}
(** Canonical Stage 1 data: product summaries and generated clause families. *)

val build_stage1 :
  node:Core_syntax.historical Ir.node_ir ->
  initial_state:Kernel_clause_projection.product_state_anchor ->
  steps:Kernel_clause_projection.product_step list ->
  is_live_state:(Kernel_clause_projection.product_state_anchor -> bool) ->
  stage1
(** Builds the canonical Stage 1 family from an already constructed IR node and
    concrete product steps. *)
