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

(** Product-reachability invariant candidates.

    This pass synthesizes a finite, conservative [true]/[false] candidate
    [R_p] for each live product state. The candidate is only a candidate:
    whenever [R_dst] is [false], the pass also injects preservation
    obligations proving that every incoming product edge to [dst] is impossible.

    The module never removes product edges. *)

type t

type strategy =
  | Trivial
  | Contradiction_closure
(** [Trivial] proposes [true] for every state. [Contradiction_closure] computes
    the conservative Boolean closure currently used by Kairos. *)

val build :
  strategy:strategy ->
  initial_state:Kr_verification_ir.product_state ->
  node:Kr_domain_core_syntax.historical Kr_verification_ir.node_ir ->
  t

val formula_of_product_state : t -> Kr_verification_ir.product_state -> 'phase Kr_domain_core_syntax.hexpr
(** [formula_of_product_state t p] returns the current [R_p] candidate. Unknown
    states default to [true], so the invariant is conservative under missing
    metadata. *)

val entry_facts_of_product_state :
  t -> Kr_verification_ir.product_state -> 'phase Kr_domain_core_syntax.hexpr list
(** Auxiliary entry facts for a step whose source is [p]. The list is
    empty when [R_p] is [true] and contains [false] when [R_p] is [false]. *)

val preservation_ensures : t -> Kr_domain_core_syntax.historical Kr_verification_ir.product_step_summary -> Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list
(** Preservation obligations for the destinations of one product summary.
    Only non-trivial obligations are returned. Their order and occurrences are
    those of the product cases; this reference pass performs no deduplication. *)
