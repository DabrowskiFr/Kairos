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

(** Compute canonical preconditions [H] from minimal grouped summaries.

    This pass enriches [requires] with:
    - propagated guarantee context from predecessor safe branches,
    - assume/program guards,
    - state-stability equalities,
    - source-state invariants.

    Initial states do not carry ordinary state invariants; this is enforced by
    the frontend/model validation boundary, so this pass does not generate
    initial invariant goals. *)

val run_program :
  ?observe_family:Ir_fact_family_metrics.observer ->
  Core_syntax.historical Ir.node_ir list ->
  Core_syntax.historical Ir.node_ir list
