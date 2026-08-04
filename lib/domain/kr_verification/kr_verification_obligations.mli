(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Backend-neutral individual obligations.

    This module is the mandatory boundary after the lowered verification IR.
    It preserves partition provenance and contract order, and makes the entry
    and exit interpretation of every step contract explicit. It performs no
    grouping, factorization, formula sharing, or postcondition bundling. *)

type partition_input = private {
  proof_case : Kr_verification_cases.proof_case;
  node : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir;
}
(** One lowered node associated with a core-owned proof case. *)

val of_instrumented_product_node :
  Kr_verification_orchestration.instrumented_product_node ->
  partition_input
(** Preserves the opaque proof-case/IR association produced and checked by the
    reference pipeline. This is the production ingress for obligations. *)

type step_obligation = private {
  id : int;
  partition_name : Kr_domain_core_syntax.ident;
  contract : Kr_verification_step_contract.step_contract;
}
(** One individual step contract with a stable node-local identifier and the
    proof-case partition from which it originates. *)

type condition = private
  | State_is of Kr_domain_core_syntax.ident
  | Formula of Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula
(** Atomic condition of an individual obligation. *)

type conjunction = condition list

type conjunction_key

val conjunction_key : conjunction -> conjunction_key
(** Stable structural key preserving condition order and polarity. *)

val normalized_conjunction_key : conjunction -> conjunction_key
(** Structural conjunction key modulo order and repeated conditions. *)

val equivalent_conjunction : conjunction -> conjunction -> bool
(** Equality modulo repeated structurally equal conditions. *)

val deduplicate_conjunction : conjunction -> conjunction
(** Keeps the first occurrence of each structurally equal condition. *)

val common_conjunction : conjunction list -> conjunction
(** Conditions common to every conjunction, in first-conjunction order. *)

val remove_conjunction : conjunction -> conjunction -> conjunction
(** Removes all conditions structurally represented by the second
    conjunction. *)

type t = private {
  semantics : Kr_verification_ir.node_signature;
  temporal_layout : Kr_verification_ir.temporal_layout;
  steps : step_obligation list;
}
(** Individual obligations for one source node. *)

val entry_conditions : step_obligation -> conjunction
(** Source control state and contract preconditions, in canonical source
    order. *)

val exit_conditions : step_obligation -> conjunction
(** Positive postconditions. *)

val formula_occurrences :
  step_obligation ->
  Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list
(** Formula occurrences carried by the underlying step contract. *)

val formulas_of_condition :
  condition ->
  Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list

val formulas_of_conditions :
  conjunction ->
  Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list

val map_formulas :
  (Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula ->
  Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula) ->
  t ->
  (t, string) result
(** Applies a representation-only transformation to every formula occurrence.
    The result is rejected unless it remains structurally equal to the input.
    This admits physical sharing while preventing optimization code from
    changing a canonical obligation. *)

val build_program :
  proof_cases:Kr_verification_cases.t ->
  partition_inputs:partition_input list ->
  (t list, string) result
(** Builds individual obligations independently in each proof-case partition,
    then assembles them by source node without regrouping or reordering them.

    The supplied inputs must cover every case of [proof_cases] exactly once.
    Foreign or duplicate provenance and incompatible temporal layouts are
    rejected at this mandatory boundary. An empty obligation family is valid:
    it represents a proof case for which the assumption monitor has no
    non-empty post-image. *)
