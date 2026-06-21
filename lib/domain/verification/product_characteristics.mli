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

(** Internal facts carried by guarantee-automaton product states.

    These facts are derived from the generated guarantee automaton, not from
    user-written invariant annotations. For a product state [p], the entry
    characteristic is normally the disjunction of safe incoming guarantee
    guards to [p], shifted to the time frame of the next step. For product
    states that are sources of a nontrivial bad-guarantee exclusion, the pass
    refines that characteristic with a disjunction of complete incoming safe
    product steps: program guard plus guarantee guard, transported to [p]'s
    entry time frame. The bad-guarantee check is not restricted to formulas
    that syntactically mention history: the monitor state itself may be the
    memory of a delayed obligation. This refinement is used only as a generated
    invariant candidate: the corresponding post-state contribution is emitted
    as an ordinary preservation obligation on every incoming safe step.

    Preservation of a characteristic along an incoming product step is emitted
    as an ordinary postcondition unless the current safe guarantee guard already
    subsumes the destination characteristic syntactically. Thus an executable
    program guard is never propagated as a raw shifted assumption: it is used
    only in this degenerate/exclusion case, and if the transition body
    invalidates the generated contribution, the corresponding proof obligation
    fails.

    Assumption automata are intentionally not propagated here: assumption guards
    are used as environment preconditions in the current backend, so treating
    them as post-state facts would only be sound under an additional
    input-only restriction. *)

type t

val build : node:Ir.node_ir -> t
(** Build the characteristic table for one node. *)

val entry_facts_of_product_state :
  t -> Ir.product_state -> Core_syntax.hexpr list
(** Facts that may be assumed at the entry of a local product step whose source
    is the given product state. *)

val preservation_ensures :
  t ->
  is_input:(Core_syntax.ident -> bool) ->
  Ir.product_step_summary ->
  Core_syntax.hexpr list
(** Preservation obligations induced by the safe destinations of one product
    summary. *)
