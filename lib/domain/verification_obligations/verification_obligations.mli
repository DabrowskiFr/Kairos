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
  proof_case : Proof_case_program.proof_case;
  node : Core_syntax.history_free Ir.node_ir;
}
(** One lowered node associated with a core-owned proof case. *)

val of_instrumented_product_node :
  Orchestration.instrumented_product_node ->
  partition_input
(** Preserves the opaque proof-case/IR association produced and checked by the
    reference pipeline. This is the production ingress for obligations. *)

val make_partition_input :
  proof_case:Proof_case_program.proof_case ->
  node:Core_syntax.history_free Ir.node_ir ->
  (partition_input, string) result
(** Constructs a typed association and rejects a lowered node whose name,
    source contract, signature, or executable transition provenance does not
    match its proof case. This explicit validation ingress is intended for
    isolated construction and tests; the runtime uses
    {!of_instrumented_product_node}. *)

type step_obligation = private {
  id : int;
  partition_name : Core_syntax.ident;
  contract : Step_contract_projection.step_contract;
}
(** One individual step contract with a stable node-local identifier and the
    partition that established its reachability requirements. *)

type condition = private
  | State_is of Core_syntax.ident
  | Formula of Core_syntax.history_free Ir.summary_formula
  | Not_formula of Core_syntax.history_free Ir.summary_formula
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
  semantics : Ir.node_signature;
  temporal_layout : Ir.temporal_layout;
  steps : step_obligation list;
}
(** Individual obligations for one source node. *)

val entry_conditions : step_obligation -> conjunction
(** Source control state and contract preconditions, in canonical source
    order. *)

val exit_conditions : step_obligation -> conjunction
(** Negated exclusions followed by positive postconditions. *)

val formula_occurrences :
  step_obligation ->
  Core_syntax.history_free Ir.summary_formula list
(** Formula occurrences carried by the underlying step contract. *)

val formulas_of_condition :
  condition ->
  Core_syntax.history_free Ir.summary_formula list

val formulas_of_conditions :
  conjunction ->
  Core_syntax.history_free Ir.summary_formula list

val build_program :
  proof_cases:Proof_case_program.t ->
  partition_inputs:partition_input list ->
  (t list, string) result
(** Builds individual obligations independently in each proof-case partition,
    then assembles them by source node without regrouping or reordering them.

    The supplied inputs must cover every case of [proof_cases] exactly once.
    Foreign or duplicate provenance, incompatible temporal layouts, and empty
    obligation families are rejected at this mandatory boundary. *)
