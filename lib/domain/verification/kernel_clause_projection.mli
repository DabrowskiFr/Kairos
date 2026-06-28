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

(** Rocq-facing kernel clauses.

    This module owns the implementation-side object corresponding to Rocq
    [KernelClause] in [Obligations/Semantics/StepContracts.v]. It deliberately
    lives in [domain/verification]: it is independent from JSON schemas, Why3
    tasks, proof-export lowering, diagnostics, and backend scheduling.

    The extra [classified_clause] wrapper records the clause-family predicate
    used by the Rocq stage-1 summary families and carries the concrete product
    step when a backend later needs to lower a step-anchored clause. The
    underlying [kernel_clause] is the formal object. *)

open Core_syntax

type time_tag =
  | PreviousTick
  | StepTickContext
  | CurrentTick
(** Time tag of a local generated fact. *)

type timed_fact_desc =
  | FactProgramState of ident
  | FactGuaranteeState of int
  | FactPhaseFormula of hexpr
  | FactFormula of hexpr
  | FactFalse
(** Atomic generated fact descriptor. *)

type timed_fact = {
  tf_time : time_tag;
  tf_desc : timed_fact_desc;
}
(** A fact together with its local time tag. *)

type product_state_anchor = Product_summary_projection.product_state_anchor
(** Product-state anchor: program state, assumption automaton state, and
    guarantee automaton state. *)

type product_step_anchor = {
  psta_src : product_state_anchor;
  psta_dst : product_state_anchor;
  psta_transition_id : string;
}
(** Rocq-level product-step anchor. *)

type product_step_class =
  | StepSafe
  | StepBadAssumption
  | StepBadGuarantee
(** Product-step class. *)

type product_step = {
  step_anchor : product_step_anchor;
  program_guard : hexpr;
  assume_guard : hexpr;
  guarantee_guard : hexpr;
  step_class : product_step_class;
}
(** Concrete product step used to instantiate step-anchored clauses.

    [step_anchor] is the Rocq anchor. The guards and class are construction
    context needed by the implementation and later backend lowering. *)

type anchor =
  | AnchorProductState of product_state_anchor
  | AnchorProductStep of product_step_anchor
(** Anchor identifying the local situation where a kernel clause applies. *)

type kernel_clause = {
  kc_anchor : anchor;
  kc_hypotheses : timed_fact list;
  kc_conclusions : timed_fact list;
}
(** Clause produced before compilation to external proof obligations. *)

type clause_context =
  | ClauseProductState of product_state_anchor
  | ClauseProductStep of product_step
(** Concrete context that generated a classified clause. *)

type classified_clause = {
  family : Obligation_family_projection.clause_family;
  context : clause_context;
  clause : kernel_clause;
}
(** Kernel clause plus its Rocq-facing family classification. *)

val product_step_anchor : product_step -> product_step_anchor
(** Returns the Rocq anchor of a concrete product step. *)

val build_source_summary_clauses :
  node:Ir.node_ir -> steps:product_step list -> classified_clause list
(** Builds source/product-summary clauses from canonical product summaries. *)

val build :
  node:Ir.node_ir ->
  initial_state:product_state_anchor ->
  steps:product_step list ->
  is_live_state:(product_state_anchor -> bool) ->
  classified_clause list
(** Builds all classified kernel clauses for one node. *)
