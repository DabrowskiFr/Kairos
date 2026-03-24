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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Construction and normalization helpers for first-order temporal
    specifications. *)

(* {1 Atom Collection} Utilities to extract atomic FO formulas from LTL/FO specs. *)

(* Collect atomic FO formulas referenced by an LTL formula. *)
val collect_atoms_ltl : Ast.ltl -> Ast.fo list -> Ast.fo list

(* Collect atomic FO formulas referenced by a FO formula. *)
val collect_atoms_fo : Ast.fo -> Ast.fo list -> Ast.fo list

(* Collect atom formulas from node-level specs and invariants. *)
val collect_atoms_from_node : Ast.node -> Ast.fo list
(* {1 Transition Helpers} *)

(* Flatten transition requires/ensures into a single list. *)
val transition_fo : Ast.transition -> Ast.ltl list

(* Conjoin a list of FO formulas, or [None] for empty. *)
val conj_fo : Ast.ltl list -> Ast.ltl option
(* {1 Expression Conversion} *)

(* Map a relational operator to its boolean binary operator. *)
val relop_to_binop : Ast.relop -> Ast.binop

type temporal_binding = {
  source_hexpr : Ast.hexpr;
  slot_names : Ast.ident list;
}

val temporal_bindings_of_pre_k_map :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list -> temporal_binding list

(* Convert a hexpr to an iexpr when representable (using pre‑k bindings). *)
val hexpr_to_iexpr_with_temporal_bindings :
  inputs:Ast.ident list ->
  var_types:(Ast.ident * Ast.ty) list ->
  temporal_bindings:temporal_binding list ->
  Ast.hexpr ->
  Ast.iexpr option

val hexpr_to_iexpr :
  inputs:Ast.ident list ->
  var_types:(Ast.ident * Ast.ty) list ->
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  Ast.hexpr ->
  Ast.iexpr option

(* Lower [pre_k] occurrences to explicit symbolic history variables. *)
val lower_hexpr_temporal_bindings :
  temporal_bindings:temporal_binding list -> Ast.hexpr -> Ast.hexpr option

val lower_hexpr_pre_k :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list -> Ast.hexpr -> Ast.hexpr option

(* Lower [pre_k] occurrences inside a first-order formula. *)
val lower_fo_temporal_bindings :
  temporal_bindings:temporal_binding list -> Ast.fo -> Ast.fo option

val lower_fo_pre_k :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list -> Ast.fo -> Ast.fo option

(* Lower [pre_k] occurrences inside an LTL formula when possible. *)
val lower_ltl_temporal_bindings :
  temporal_bindings:temporal_binding list -> Ast.ltl -> Ast.ltl option

val lower_ltl_pre_k :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list -> Ast.ltl -> Ast.ltl option

(* Infer a simple type for an iexpr from variable types. *)
val infer_iexpr_type : var_types:(Ast.ident * Ast.ty) list -> Ast.iexpr -> Ast.ty option

(* Boolean equality encoded as a pure boolean expression. *)
val mk_bool_eq : Ast.iexpr -> Ast.iexpr -> Ast.iexpr

(* Boolean inequality encoded as a pure boolean expression. *)
val mk_bool_neq : Ast.iexpr -> Ast.iexpr -> Ast.iexpr

(* Convert an atomic FO predicate to an iexpr when possible. *)
val atom_to_iexpr :
  inputs:Ast.ident list ->
  var_types:(Ast.ident * Ast.ty) list ->
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  Ast.fo ->
  Ast.iexpr option

(* Encode an atom variable as a FO relation (var = true). *)
val atom_to_var_rel : Ast.ident -> Ast.fo

(* Reconstruct FO LTL by inlining atom variables from a name->atom map. *)
val iexpr_to_fo_with_atoms : (Ast.ident * Ast.fo) list -> Ast.iexpr -> Ast.ltl
(* {1 Atom Replacement} *)

(* Replace atom formulas by their variable representation in LTL. *)
val replace_atoms_ltl : (Ast.fo * Ast.ident) list -> Ast.ltl -> Ast.ltl

(* Replace atom formulas by their variable representation in FO. *)
val replace_atoms_fo : (Ast.fo * Ast.ident) list -> Ast.fo -> Ast.fo

(* Replace atom formulas inside monitor state-relation invariants. *)
val replace_atoms_invariants_state_rel :
  (Ast.fo * Ast.ident) list -> Ast.invariant_state_rel list -> Ast.invariant_state_rel list

(* Replace atom formulas inside a transition. *)
val replace_atoms_transition : (Ast.fo * Ast.ident) list -> Ast.transition -> Ast.transition

(* {1 Fold Diagnostics} *)
(* Fold-specific diagnostics removed. *)
(* {1 Instrumentation Specs} *)

(* Build the monitorized temporal spec.
   Current policy: only guarantees are monitorized; assumptions are handled as proof hypotheses. *)
val combine_contracts_for_monitor :
  assumes:Ast.ltl list -> guarantees:Ast.ltl list -> Ast.ltl
