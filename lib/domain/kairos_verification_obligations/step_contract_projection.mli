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

type step_contract = {
  transition_id : string;
  program_step : Ir.transition;
  monitor_source : Ir.monitor_state_pair;
  assume_guard : Core_syntax.history_free Ir.summary_formula;
  requires : Core_syntax.history_free Ir.summary_formula list;
  ensures : Core_syntax.history_free Ir.summary_formula list;
  elaboration_checks : Core_syntax.history_free Ir.summary_formula list;
}
(** Step contract before backend-specific lowering. *)

val product_source : step_contract -> Ir.product_state
(** Derives the complete product source from the program transition and
    monitor-source indices stored by the contract. *)

val preconditions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Preconditions already carried by the enriched IR, followed by the
    assumption guard. *)

val postconditions : step_contract -> Core_syntax.history_free Ir.summary_formula list
(** Positive postconditions of a step contract. *)

val of_ir_node :
  Core_syntax.history_free Ir.node_ir ->
  step_contract list
(** Extracts step contracts directly from enriched IR summaries. *)
