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

(** Backend-neutral step contracts derived from the enriched verification IR.

    This module is the single contract-preparation boundary between
    {!Ir.product_step_summary} and proof backends. It is independent from Why3
    terms, helper grouping, worker scheduling, dumps, and solver results. *)

open Core_syntax

type step_class =
  | StepSafe
  | StepBadGuarantee
(** Contract class kept by the current proof backend. Bad-assumption product
    steps are discharged by assumption violation and do not become Why3 step
    contracts. *)

type step_contract = {
  transition_id : string;
  program_step : Ir.transition;
  step_class : step_class;
  product_src : Ir.product_state;
  assume_guard : Core_syntax.history_free Ir.summary_formula;
  requires : Core_syntax.history_free Ir.summary_formula list;
  runtime_requires : Core_syntax.history_free Ir.summary_formula list;
  ensures : Core_syntax.history_free Ir.summary_formula list;
  elaboration_checks : Core_syntax.history_free Ir.summary_formula list;
  forbidden : Core_syntax.history_free Ir.summary_formula list;
}
(** Step contract before backend-specific lowering. *)

val preconditions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Preconditions of a step contract, including its assumption guard and
    requirements induced by product reachability. *)

val postconditions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Positive postconditions of a step contract. *)

val exclusions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Formulas excluded by a bad-guarantee step. Top-level disjunctions are split
    once during contract construction; backends discharge each resulting
    clause by requiring its negation. *)

val of_ir_node :
  Core_syntax.history_free Ir.node_ir ->
  step_contract list
(** Extracts step contracts directly from enriched IR summaries and adds the
    requirements induced by product reachability. *)
