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
    {!Kr_verification_ir.product_step_summary} and proof backends. It is independent from Why3
    terms, helper grouping, worker scheduling, dumps, and solver results. *)

type step_contract = {
  transition_id : string;
  program_step : Kr_verification_ir.transition;
  monitor_source : Kr_verification_ir.monitor_state_pair;
  assume_guard : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula;
  requires : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list;
  ensures : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list;
  elaboration_checks : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list;
}
(** Step contract before backend-specific lowering. *)

val product_source : step_contract -> Kr_verification_ir.product_state
(** Derives the complete product source from the program transition and
    monitor-source indices stored by the contract. *)

val preconditions : step_contract -> Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list
(** Preconditions already carried by the enriched IR, followed by the
    assumption guard. *)

val postconditions : step_contract -> Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list
(** Positive postconditions of a step contract. *)

val of_ir_node :
  Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir ->
  step_contract list
(** Extracts step contracts directly from enriched IR summaries. *)
