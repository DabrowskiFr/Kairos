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

(** Compute canonical postconditions [D] and product-case payloads.

    This pass enriches minimal/pre summaries by materializing:
    - postcondition [D] as the disjunction of guarantee-successor guards
      (explicitly [false] when the post is empty),
    - each destination invariant shifted in post-state coordinates and guarded
      by the corresponding product case before being injected into
      [ensures].

    The reference pass preserves occurrences and does not factor invariants
    shared by several destinations. Such factorization is a proof-shape
    optimization and must be applied explicitly after this boundary if its
    measured gain justifies it.

    [product_invariants] contains the selected auxiliary invariant analyses for
    each input node, in the same order. *)

val run_program :
  ?observe_family:Kr_verification_fact_metrics.observer ->
  product_invariants:Product_invariant.t list list ->
  Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
  Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list
