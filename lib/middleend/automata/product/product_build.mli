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
    - the assumption automaton;
    - the guarantee automaton.

    The builder explores reachable triples [(P, A, G)] from the initial state
    and records one {!Product_types.product_step} for every local combination of
    program transition, assumption edge, and guarantee edge. *)

(** Alias used by downstream code. *)
type analysis = Product_analysis.analysis

val analyze_node :
  build:Automaton_types.automata_build ->
  node:Ir.node ->
  analysis
(** [analyze_node ~build ~node] explores the explicit product associated with
    [node] using the automata already built in [build].

    The result contains:
    - the reachable product states;
    - the explicit product steps between them;
    - the bad-state indices and rendering metadata required downstream. *)
