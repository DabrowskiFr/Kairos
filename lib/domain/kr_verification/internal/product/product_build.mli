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

(** Explicit construction of the product between:
    - the normalized program control graph of one node;
    - the deterministic partial assumption monitor;
    - the deterministic partial guarantee monitor.

    The builder explores reachable triples [(P, A, G)] directly over producer
    states. It neither determinizes monitors nor enumerates valuations.

    Every enabled program–assumption edge is recorded once as a
    {!Kr_verification_product.product_prefix}. Its guarantee successors are stored
    directly by that prefix. Their guard disjunction expresses progress; it
    need not cover every valuation. An empty successor list denotes blocking. *)

(** Structurally valid producer monitors whose historical guards have passed
    the domain-owned availability validation. *)
type validated_automata_spec

(** [validate_automata_spec build] validates historical guard availability. A
    guard leaving a state whose minimum structural age is [n] may read history
    only through depth [n]. *)
val validate_automata_spec :
  Kr_verification_automata_types.automata_spec -> validated_automata_spec

(** [analyze_node ~build ~node] explores the explicit product associated with
    [node] using an already validated monitor pair.

    The result contains:
    - the initial product state;
    - program–assumption prefixes with their guarantee successors;
    - the raw producer monitors required by renderers. *)
val analyze_node :
  build:validated_automata_spec ->
  node:Kr_domain_core_model.node_model ->
  program_transitions:Kr_domain_core_model.program_step list ->
  Kr_verification_temporal_automata.node_data
