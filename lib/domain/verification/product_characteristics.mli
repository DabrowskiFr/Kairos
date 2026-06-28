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
    input-only restriction.

    Architecture invariant: every formula returned by
    {!entry_facts_of_product_state} must satisfy
    [Fo_current_input.no_current_input] for the node inputs. This is not a
    user obligation and not a Rocq theorem inventory generated from OCaml.
    It is the local well-formedness condition that keeps generated
    product-state facts in the end-of-instant phase. Current input
    occurrences must be shifted to [pre]/[pre_k] before the fact can become an
    end-of-instant product-state fact; otherwise construction should fail
    rather than filtering the formula away.

    The local preservation checklist for this invariant is:
    {ul
    {- [no_current_input_simplify_fo]:
       [no_current_input inputs f] implies
       [no_current_input inputs (simplify_fo f)].}
    {- [no_current_input_bool_constructors]:
       [mk_hand], [mk_hor], [mk_himp], [term_not], and top-level boolean
       flattening preserve [no_current_input] when their operands do.}
    {- [no_current_input_dedup_formulas]:
       [dedup_formulas] preserves the property elementwise, because it only
       simplifies, keys, sorts, and removes duplicates.}
    {- [no_current_input_disj_fo]:
       if every input formula is current-input-free, then any formula returned
       by [disj_fo] is current-input-free.}
    {- [shift_formula_forward_inputs_no_current_input]:
       [shift_formula_forward_inputs] turns every current input occurrence into
       a historical [pre]/[pre_k] occurrence, so its result is
       current-input-free even if the source formula was not.}
    {- [shift_hexpr_forward_all_no_current_input]:
       [shift_hexpr_forward_all] turns every variable occurrence into a
       historical occurrence, so its result is current-input-free.}
    {- [program_entry_formula_no_current_input]:
       the formula
       [shift_hexpr_forward_all program_guard
        && shift_formula_forward_inputs admissible_guard]
       is current-input-free.}
    {- [entry_fact_no_current_input]:
       every [entry_fact] stored in the characteristic table is
       current-input-free. The normal branch follows from
       [shift_formula_forward_inputs_no_current_input]; the refined branch
       follows from [program_entry_formula_no_current_input] and
       [no_current_input_disj_fo].}
    {- [entry_facts_of_product_state_no_current_input]:
       every formula returned by [entry_facts_of_product_state] is
       current-input-free.}
    }

    [shift_formula_forward_non_inputs] is deliberately not in this list: it
    preserves current input occurrences. It is used for post-state preservation
    obligations, not for exported entry facts. *)

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
