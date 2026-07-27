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

(** Generated facts carried by selected product states.

    User state invariants and these characteristics are distinct. For each safe
    incoming product case, the post-state contribution is the conjunction of:
    the source control-state annotation and executable guard transported from
    tick entry to the post-state frame, the selected assumption-automaton
    guard, the compatible guarantee-automaton guard, and a conservative
    symbolic summary of the transition body's effect. The destination
    characteristic is the disjunction of those contributions, transported to
    the next tick-entry frame with {!Fo_time.shift_formula_forward_inputs}.

    Characteristics are generated only for product states from which a
    guarantee-bad case is structurally possible. Their preservation is emitted
    as an ordinary postcondition on every safe incoming case. Consequently, an
    imprecise body summary can reject a valid program but cannot justify an
    invalid one: the backend must prove the propagated contribution after
    executing the actual transition body.

    Every entry fact returned by {!entry_facts_of_product_state} is free of
    current-input reads. Current inputs in a post-state contribution become
    historical reads before the contribution is stored as a persistent product
    characteristic. In particular, current inputs in an assumption guard are
    retained as historical facts about the tick that reached the state. *)

type t

val build : node:Core_syntax.historical Ir.node_ir -> t
(** Build the characteristic table for one node. *)

val entry_facts_of_product_state :
  t -> Ir.product_state -> Core_syntax.historical Core_syntax.hexpr list
(** Facts that may be assumed at the entry of a local product step whose source
    is the given product state. *)

val preservation_ensures :
  t ->
  node:Core_syntax.historical Ir.node_ir ->
  Core_syntax.historical Ir.product_step_summary ->
  Core_syntax.historical Core_syntax.hexpr list
(** Preservation obligations induced by the safe destinations of one product
    summary. *)
