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

(** Compute canonical postconditions [D] and branch payloads.

    This pass enriches minimal/pre summaries by materializing:
    - admissible/excluded branch guards,
    - postcondition [D] as safe disjunction,
    - destination invariants shifted in post-state coordinates and injected
      into [ensures].

    [product_characteristics] contains one analysis per input node, in the same
    order. *)

val run_program :
  ?observe_family:Ir_fact_family_metrics.observer ->
  product_characteristics:Product_characteristics.t list ->
  Core_syntax.historical Ir.node_ir list ->
  Core_syntax.historical Ir.node_ir list
