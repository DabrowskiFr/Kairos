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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type anchor_kind =
  | ProductStateAnchor
  | ProductStepAnchor

type clause_group =
  | SourceClause
  | PhasePreClause
  | PhaseClause
  | SafetyClause
  | InitClause
  | PropagationClause

type clause_family =
  | SourceProductSummary
  | PhaseStepPreSummary
  | PhaseStepSummary
  | Safety
  | InitNodeInvariant
  | InitAutomatonCoherence
  | PropagationNodeInvariant
  | PropagationAutomatonCoherence

let all_clause_families =
  [
    SourceProductSummary;
    PhaseStepPreSummary;
    PhaseStepSummary;
    Safety;
    InitNodeInvariant;
    InitAutomatonCoherence;
    PropagationNodeInvariant;
    PropagationAutomatonCoherence;
  ]

let group = function
  | SourceProductSummary -> SourceClause
  | PhaseStepPreSummary -> PhasePreClause
  | PhaseStepSummary -> PhaseClause
  | Safety -> SafetyClause
  | InitNodeInvariant | InitAutomatonCoherence -> InitClause
  | PropagationNodeInvariant | PropagationAutomatonCoherence ->
      PropagationClause

let expected_anchor_kind = function
  | SourceProductSummary | InitNodeInvariant | InitAutomatonCoherence ->
      ProductStateAnchor
  | PhaseStepPreSummary | PhaseStepSummary | Safety
  | PropagationNodeInvariant | PropagationAutomatonCoherence ->
      ProductStepAnchor

let stable_name = function
  | SourceProductSummary -> "source_product_summary"
  | PhaseStepPreSummary -> "phase_step_pre_summary"
  | PhaseStepSummary -> "phase_step_summary"
  | Safety -> "safety"
  | InitNodeInvariant -> "init_node_invariant"
  | InitAutomatonCoherence -> "init_automaton_coherence"
  | PropagationNodeInvariant -> "propagation_node_invariant"
  | PropagationAutomatonCoherence -> "propagation_automaton_coherence"

let of_stable_name raw =
  List.find_opt
    (fun family -> String.equal (stable_name family) raw)
    all_clause_families

let display_name = function
  | SourceProductSummary -> "source/product_summary"
  | PhaseStepPreSummary -> "phase/step_pre_summary"
  | PhaseStepSummary -> "phase/step_summary"
  | Safety -> "safety"
  | InitNodeInvariant -> "init/node_inv"
  | InitAutomatonCoherence -> "init/automaton"
  | PropagationNodeInvariant -> "propagation/node_inv"
  | PropagationAutomatonCoherence -> "propagation/automaton"

let proof_role = function
  | SourceProductSummary ->
      "reconstructs product-state phase facts from incoming safe summaries"
  | PhaseStepPreSummary ->
      "makes previous-tick phase compatibility available at a product step"
  | PhaseStepSummary ->
      "proves that the guarantee automaton edge is compatible with the step"
  | Safety -> "excludes a bad-guarantee product step"
  | InitNodeInvariant -> "establishes initial program-state invariants"
  | InitAutomatonCoherence -> "establishes initial guarantee automaton state"
  | PropagationNodeInvariant ->
      "preserves program state and destination invariants across a step"
  | PropagationAutomatonCoherence ->
      "preserves guarantee automaton state coherence across a step"

let is_source_clause family = group family = SourceClause
let is_phase_pre_clause family = group family = PhasePreClause
let is_phase_clause family = group family = PhaseClause
let is_safety_clause family = group family = SafetyClause
let is_init_clause family = group family = InitClause
let is_propagation_clause family = group family = PropagationClause
