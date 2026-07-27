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

(** Canonical proof-obligation families before derived views and backends.

    This module names the implementation-side objects that should be compared
    with the Rocq Stage 1 and Stage 2 principles. It does not own JSON export,
    Why3 grouping, diagnostics, solver scheduling, or proof artifacts. *)

type stage1 = {
  product_summaries :
    Core_syntax.historical Product_summary_projection.t;
  clauses : Kernel_clause_projection.classified_clause list;
}
(** Canonical Stage 1 data: product summaries and generated clause families. *)

val build_stage1 :
  node:Core_syntax.historical Ir.node_ir ->
  initial_state:Kernel_clause_projection.product_state_anchor ->
  steps:Kernel_clause_projection.product_step list ->
  is_live_state:(Kernel_clause_projection.product_state_anchor -> bool) ->
  stage1
(** Builds the canonical Stage 1 family from an already constructed IR node and
    concrete product steps. *)

type step_class =
  | StepSafe
  | StepBadGuarantee
(** Canonical Stage 2 contract class. Bad-assumption steps do not become
    program-step contracts. *)

type 'phase covered_case =
  | CoveredSafeCase of 'phase Ir.safe_product_case
  | CoveredUnsafeCase of 'phase Ir.unsafe_product_case
(** Product case covered by a canonical step contract. *)

type 'phase step_contract = {
  transition_id : string;
  program_transition_id : int;
  program_step : Ir.transition;
  step_class : step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  assume_guard : 'phase Ir.summary_formula;
  requires : 'phase Ir.summary_formula list;
  runtime_requires : 'phase Ir.summary_formula list;
  propagates : 'phase Ir.summary_formula list;
  ensures : 'phase Ir.summary_formula list;
  elaboration_checks : 'phase Ir.summary_formula list;
  forbidden : 'phase Ir.summary_formula list;
  summary_identity : 'phase Product_summary_projection.summary_identity;
  covered_cases : 'phase covered_case list;
}
(** Canonical Stage 2 step contract.

    Safe contracts cover all safe cases of one summary. Unsafe contracts are
    intentionally one-per-unsafe-case, matching the Rocq proof principle before
    any backend grouping or top-level disjunction splitting. *)

type 'phase stage2 = {
  product_summaries : 'phase Product_summary_projection.t;
  step_contracts : 'phase step_contract list;
}
(** Canonical Stage 2 contracts for one node. *)

val build_stage2 :
  'phase Product_summary_projection.t -> 'phase stage2
(** Extracts the canonical Stage 2 family from product summaries. *)
