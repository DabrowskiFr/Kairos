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

(** {1 Atom Collection}
    Utilities to extract atomic FO formulas from LTL/FO specs. *)

(** Collect atomic FO formulas referenced by an LTL formula. *)
val collect_atoms_ltl : Ast.fo_ltl -> Ast.fo list -> Ast.fo list
(** Collect atomic FO formulas referenced by a FO formula. *)
val collect_atoms_fo : Ast.fo -> Ast.fo list -> Ast.fo list
(** Collect atom formulas from node-level specs and invariants. *)
val collect_atoms_from_node : Ast.node -> Ast.fo list
(** {1 Transition Helpers} *)

(** Flatten transition requires/ensures into a single list. *)
val transition_fo : Ast.transition -> Ast.fo list
(** Conjoin a list of FO formulas, or [None] for empty. *)
val conj_fo : Ast.fo list -> Ast.fo option
(** {1 Expression Conversion} *)

(** Map a relational operator to its boolean binary operator. *)
val relop_to_binop : Ast.relop -> Ast.binop
(** Convert a hexpr to an iexpr when representable (using pre‑k bindings). *)
val hexpr_to_iexpr :
  inputs:Ast.ident list ->
  var_types:(Ast.ident * Ast.ty) list ->
  pre_k_map:(Ast.hexpr * Support.pre_k_info) list ->
  Ast.hexpr -> Ast.iexpr option
(** Infer a simple type for an iexpr from variable types. *)
val infer_iexpr_type :
  var_types:(Ast.ident * Ast.ty) list -> Ast.iexpr -> Ast.ty option
(** Boolean equality encoded as a pure boolean expression. *)
val mk_bool_eq : Ast.iexpr -> Ast.iexpr -> Ast.iexpr
(** Boolean inequality encoded as a pure boolean expression. *)
val mk_bool_neq : Ast.iexpr -> Ast.iexpr -> Ast.iexpr
(** Convert an atomic FO predicate to an iexpr when possible. *)
val atom_to_iexpr :
  inputs:Ast.ident list ->
  var_types:(Ast.ident * Ast.ty) list ->
  pre_k_map:(Ast.hexpr * Support.pre_k_info) list ->
  Ast.fo -> Ast.iexpr option
(** Encode an atom variable as a FO relation (var = true). *)
val atom_to_var_rel : Ast.ident -> Ast.fo
(** Reconstruct FO by inlining atom variables from a name->atom map. *)
val iexpr_to_fo_with_atoms : (Ast.ident * Ast.fo) list -> Ast.iexpr -> Ast.fo
(** {1 Atom Replacement} *)

(** Replace atom formulas by their variable representation in LTL. *)
val replace_atoms_ltl : (Ast.fo * Ast.ident) list -> Ast.fo_ltl -> Ast.fo_ltl
(** Replace atom formulas by their variable representation in FO. *)
val replace_atoms_fo : (Ast.fo * Ast.ident) list -> Ast.fo -> Ast.fo
(** Replace atom formulas inside monitor state-relation invariants. *)
val replace_atoms_invariants_state_rel :
  (Ast.fo * Ast.ident) list ->
  Ast.invariant_state_rel list -> Ast.invariant_state_rel list
(** Replace atom formulas inside a transition. *)
val replace_atoms_transition :
  (Ast.fo * Ast.ident) list -> Ast.transition -> Ast.transition
(** {1 Fold Diagnostics} *)
(** Fold-specific diagnostics removed. *)
(** {1 Monitor Specs} *)

(** Combine assume/guarantee lists into a single monitor spec. *)
val combine_contracts_for_monitor :
  assumes:Ast.fo_ltl list -> guarantees:Ast.fo_ltl list -> Ast.fo_ltl
