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

(** Expand the selectors attached to surface state invariants.

    Selectors may name one state, a set, all states or a set difference. This
    module validates those names and produces one invariant occurrence per
    selected concrete state. *)

val resolve_state_selector :
  node_name:string ->
  states:string list ->
  Kx_surface_ast.state_selector ->
  string list
(** Resolve one selector in declaration order, rejecting unknown or duplicate
    state names. *)

val expand_state_invariants :
  Kx_surface_ast.node -> (string * Kx_surface_syntax.hexpr) list
(** Pair every state invariant with each selected state. Empty selections and
    explicit selection of a visible initial state are rejected. *)
