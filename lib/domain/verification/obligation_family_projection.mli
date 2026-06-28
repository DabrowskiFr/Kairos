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

(** Semantic classification of generated obligations.

    These constructors are not diagnostic provenance. They name the proof
    schema instantiated by a generated clause, so the implementation can expose
    the same families that the Rocq development reasons about. *)

type anchor_kind =
  | ProductStateAnchor
  | ProductStepAnchor
(** Shape of the product anchor expected by a family. *)

type clause_group =
  | SourceClause
  | PhasePreClause
  | PhaseClause
  | SafetyClause
  | InitClause
  | PropagationClause
(** Coarser Rocq-facing family predicates. *)

type clause_family =
  | SourceProductSummary
  | PhaseStepPreSummary
  | PhaseStepSummary
  | Safety
  | InitNodeInvariant
  | InitAutomatonCoherence
  | PropagationNodeInvariant
  | PropagationAutomatonCoherence
(** Proof schema instantiated by one generated clause. *)

val all_clause_families : clause_family list

val group : clause_family -> clause_group
(** Rocq-facing family predicate containing the clause family. *)

val expected_anchor_kind : clause_family -> anchor_kind
(** Anchor shape expected for clauses of this family. *)

val stable_name : clause_family -> string
(** Stable snake-case name for serialization and diagnostics. *)

val of_stable_name : string -> clause_family option
(** Parses {!stable_name}. *)

val display_name : clause_family -> string
(** Short human-readable name. *)

val proof_role : clause_family -> string
(** One-line statement of the proof role of the family. *)

val is_source_clause : clause_family -> bool
val is_phase_pre_clause : clause_family -> bool
val is_phase_clause : clause_family -> bool
val is_safety_clause : clause_family -> bool
val is_init_clause : clause_family -> bool
val is_propagation_clause : clause_family -> bool
