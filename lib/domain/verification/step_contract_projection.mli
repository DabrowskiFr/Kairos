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

(** Derived grouped step-contract view used by backends.

    The canonical Stage 2 family is owned by {!Canonical_obligations}. This
    module groups that family into the historical backend view while keeping
    the canonical contracts available for adequacy checks. It is intentionally
    independent from Why3 terms, helper grouping, worker scheduling, dumps, and
    solver results. *)

open Core_syntax

type step_class = Canonical_obligations.step_class =
  | StepSafe
  | StepBadGuarantee
(** Contract class kept by the current proof backend. Bad-assumption product
    steps are discharged by assumption violation and do not become Why3 step
    contracts. *)

type covered_case =
  Core_syntax.history_free Canonical_obligations.covered_case
(** Product-summary case covered by a generated step contract. *)

type step_contract = {
  transition_id : string;
  program_transition_id : int;
  program_step : Ir.transition;
  step_class : step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  assume_guard : Core_syntax.history_free Ir.summary_formula;
  requires : Core_syntax.history_free Ir.summary_formula list;
  runtime_requires : Core_syntax.history_free Ir.summary_formula list;
  propagates : Core_syntax.history_free Ir.summary_formula list;
  ensures : Core_syntax.history_free Ir.summary_formula list;
  elaboration_checks : Core_syntax.history_free Ir.summary_formula list;
  forbidden : Core_syntax.history_free Ir.summary_formula list;
  summary_identity :
    Core_syntax.history_free Product_summary_projection.summary_identity;
  covered_cases : covered_case list;
}
(** Step contract before backend-specific lowering. *)

type t = {
  canonical : Core_syntax.history_free Canonical_obligations.stage2;
  product_summaries :
    Core_syntax.history_free Product_summary_projection.t;
  step_contracts : step_contract list;
  formula_index : Contract_formula_index.t;
}
(** Grouped step-contract view for one node.

    [canonical] is the ungrouped Stage 2 family. [step_contracts] is the
    grouped backend-facing view derived from it. *)

val preconditions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Preconditions of a step contract, including its assumption guard and
    requirements induced by product reachability. *)

val postconditions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Positive postconditions of a step contract. *)

val exclusions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Formulas excluded by a bad-guarantee step. Backends discharge them by
    requiring their negation. *)

val of_product_summaries :
  Core_syntax.history_free Product_summary_projection.t -> t
(** Extracts step contracts from an existing product-summary view. *)

val of_ir_node : Core_syntax.history_free Ir.node_ir -> t
(** Builds product summaries with current runtime requirements and extracts
    step contracts from them. *)
