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

(** Derived product-summary view used to inspect Rocq-aligned objects.

    This module is a domain-level view of the product summaries carried by
    {!Ir}. It gives a stable owner to the objects corresponding to Rocq
    [ProofStepSummary] and [SummaryClauseFamilies] inputs. It is not the
    semantic source of the theorem, and it does not depend on proof-export
    JSON, Why3 terms, diagnostics, or backend planning. *)

open Core_syntax

type product_state_anchor = Ir.product_state
(** Product state anchor: program state, assumption automaton state, and
    guarantee automaton state. *)

type product_step_anchor = {
  product_src : product_state_anchor;
  product_dst : product_state_anchor;
  program_transition_id : int;
}
(** Product step anchor projected from a summary case. *)

type summary_identity = {
  program_transition_id : int;
  program_step : Ir.transition;
  product_src : product_state_anchor;
  assume_guard : hexpr;
}
(** Identity of one proof-step summary. *)

type summary = {
  identity : summary_identity;
  propagation_requires : Ir.summary_formula list;
  requires : Ir.summary_formula list;
  runtime_requires : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
  elaboration_checks : Ir.summary_formula list;
  safe_cases : Ir.safe_product_case list;
  unsafe_cases : Ir.unsafe_product_case list;
  source_summary : Ir.product_step_summary;
}
(** Explicit projection of one product summary.

    [ensures] is the canonical Rocq-facing postcondition set.
    [elaboration_checks] carries frontend-desugaring checks that may still be
    proved by backends but are not part of Rocq [pssEnsures]. *)

type t = { summaries : summary list }
(** Product-summary projection for one node. *)

val of_ir_node :
  ?runtime_requires_of_summary:
    (Ir.product_step_summary -> Ir.summary_formula list) ->
  Ir.node_ir ->
  t
(** Builds the product-summary projection for a node.

    [runtime_requires_of_summary] can be used by later projections to attach
    generated runtime requirements. The default is empty, so diagnostic/export
    clients do not allocate fresh formula identifiers accidentally. *)

val find_by_identity :
  t ->
  program_transition_id:int ->
  product_src:product_state_anchor ->
  assume_guard:hexpr ->
  summary option
(** Finds a projected summary by its identity fields. *)

val same_product_state : product_state_anchor -> product_state_anchor -> bool
(** Structural equality for product-state anchors. *)
