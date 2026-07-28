(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Core-owned prover-independent representation of proof compilation.

    The minimal representation contains exactly one individual proof unit per
    canonical verification obligation, in source order, with inline conditions
    and no sharing. Optional optimization passes may only transform values of
    this same type. *)

module Obligations = Verification_obligations

type individual = private {
  index : int;
  member : Obligations.step_obligation;
  preconditions : Obligations.conjunction;
  postconditions : Obligations.conjunction;
  shared_postcondition_id : int option;
}

type conditional_post = private {
  alternatives : Obligations.conjunction list;
  conclusions : Obligations.conjunction;
}

type grouped = private {
  index : int;
  representative : Obligations.step_obligation;
  members : Obligations.step_obligation list;
  precondition_alternatives : Obligations.conjunction list;
  common_preconditions : Obligations.conjunction;
  conditional_posts : conditional_post list;
}

type obligation =
  | Individual of individual
  | Grouped of grouped

type shared_postcondition = private {
  id : int;
  conditions : Obligations.conjunction;
}

type shared_formula = private {
  id : int;
  formula : Core_syntax.history_free Ir.summary_formula;
  occurrence_ids : Ir_shared_types.formula_id list;
}

type t = private {
  source : Obligations.t;
  obligations : obligation list;
  shared_formulas : shared_formula list;
  shared_postconditions : shared_postcondition list;
}

val minimal : Obligations.t -> t
val minimal_program : Obligations.t list -> t list

val make_individual :
  index:int ->
  member:Obligations.step_obligation ->
  preconditions:Obligations.conjunction ->
  postconditions:Obligations.conjunction ->
  shared_postcondition_id:int option ->
  individual

val with_shared_postcondition_id :
  individual ->
  int option ->
  individual

val make_conditional_post :
  alternatives:Obligations.conjunction list ->
  conclusions:Obligations.conjunction ->
  conditional_post

val make_grouped :
  index:int ->
  representative:Obligations.step_obligation ->
  members:Obligations.step_obligation list ->
  precondition_alternatives:Obligations.conjunction list ->
  common_preconditions:Obligations.conjunction ->
  conditional_posts:conditional_post list ->
  grouped

val make_shared_postcondition :
  id:int ->
  conditions:Obligations.conjunction ->
  shared_postcondition

val make_shared_formula :
  id:int ->
  formula:Core_syntax.history_free Ir.summary_formula ->
  occurrence_ids:Ir_shared_types.formula_id list ->
  shared_formula

val rebuild :
  t ->
  obligations:obligation list ->
  shared_formulas:shared_formula list ->
  shared_postconditions:shared_postcondition list ->
  (t, string) result
(** Validate and replace the optional representation choices.

    Every canonical source obligation must occur exactly once among individual
    or grouped members, and no foreign obligation may be introduced.
    Individual and grouped pre/postconditions must encode the canonical
    conjunctions modulo duplicate occurrences. Shared definitions must refer
    to structurally equal source occurrences and be reused. *)

val obligation_members : obligation -> Obligations.step_obligation list
val shared_formula_definitions : t -> shared_formula list

val shared_formula_for :
  t ->
  Core_syntax.history_free Ir.summary_formula ->
  shared_formula option
