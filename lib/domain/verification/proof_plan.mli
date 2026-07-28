(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Backend-independent planning of product-step proof obligations.

    Reachability is computed independently in every reference partition before
    this module is called. Planning may factor obligations that execute the
    same source transition, but it never merges product summaries, automata, or
    product-state identities. *)

type policy = {
  group_safe_step_contracts : bool;
}

type partition_input = {
  source_node_name : Core_syntax.ident;
  node : Core_syntax.history_free Ir.node_ir;
}

type member = private {
  partition_name : Core_syntax.ident;
  contract : Step_contract_projection.step_contract;
}
(** One contract together with the reference partition that established its
    reachability requirements. *)

type condition = private
  | State_is of Core_syntax.ident
  | Formula of Core_syntax.history_free Ir.summary_formula
  | Not_formula of Core_syntax.history_free Ir.summary_formula
(** Atomic planned condition. Historical reads have already been lowered by
    {!Temporal_lower}; their slots remain described by [t.temporal_layout]. *)

type conjunction = condition list

type individual = private {
  index : int;
  member : member;
  preconditions : conjunction;
  postconditions : conjunction;
  shared_postcondition_id : int option;
}
(** An individual Hoare-style step obligation. [preconditions] are interpreted
    at step entry and [postconditions] at step exit. *)

type conditional_post = private {
  alternatives : conjunction list;
  conclusions : conjunction;
}
(** A factored implication [(pre_1 \/ ... \/ pre_n) -> conclusions].
    Alternatives are interpreted on the saved entry state and conclusions on
    the exit state. *)

type grouped = private {
  index : int;
  representative : member;
  members : member list;
  precondition_alternatives : conjunction list;
  common_preconditions : conjunction;
  conditional_posts : conditional_post list;
}
(** One safe executable transition shared by several contracts.

    [precondition_alternatives] is the exact disjunction enabling the helper.
    [common_preconditions] and [conditional_posts] are the backend-independent
    factorization of the relational postcondition; no backend may regroup
    them. *)

type obligation = private
  | Individual of individual
  | Grouped of grouped

type shared_postcondition = private {
  id : int;
  conditions : conjunction;
}
(** Explicit sharing decision for an individual multi-clause postcondition. *)

type t = private {
  semantics : Ir.node_signature;
  temporal_layout : Ir.temporal_layout;
  formula_index : Contract_formula_index.t;
  obligations : obligation list;
  shared_postconditions : shared_postcondition list;
}
(** Complete proof-compilation plan for one source node. The source signature
    and temporal layout define the translation context; all logical
    grouping, factorization, and formula-sharing decisions are already fixed. *)

val formulas_of_condition :
  condition ->
  Core_syntax.history_free Ir.summary_formula list

val formulas_of_conditions :
  condition list ->
  Core_syntax.history_free Ir.summary_formula list

val obligation_contract :
  obligation ->
  Step_contract_projection.step_contract

val obligation_members : obligation -> member list

val build_program :
  policy:policy ->
  source_model:Verification_model.program_model ->
  partition_inputs:partition_input list ->
  t list
(** Builds one plan per source node that has reference partitions.

    Reachability is first computed separately for every partition. Planning
    may combine safe contracts for the same executable transition, while
    retaining every member and its partition provenance. Invalid temporal
    layouts, unknown provenance, and empty obligation families are rejected
    here rather than repaired by a backend. *)
