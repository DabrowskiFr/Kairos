(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

(** {1 Atom Collection} *)

(** Collect atoms ltl. *)
val collect_atoms_ltl : Ast.fo_ltl -> Ast.fo list -> Ast.fo list
(** Collect atomic FO formulas referenced by an LTL formula. *)
val collect_atoms_fo : Ast.fo -> Ast.fo list -> Ast.fo list
(** Collect atomic FO formulas referenced by a FO formula. *)
val collect_atoms_from_node : Ast_contracts.node -> Ast.fo list
(** Collect atom formulas from node-level specs and invariants. *)
(** {1 Transition Helpers} *)

val transition_fo : Ast_contracts.transition -> Ast.fo list
(** Flatten transition requires/ensures/lemmas into a single list. *)
val conj_fo : Ast.fo list -> Ast.fo option
(** Conjoin a list of FO formulas, or None for empty. *)
(** {1 Expression Conversion} *)

val relop_to_binop : Ast.relop -> Ast.binop
(** Map a relational operator to its boolean binary operator. *)
val fold_var_of_hexpr :
  (Ast.hexpr * Ast.ident) list -> Ast.hexpr -> Ast.ident option
(** Resolve a fold accumulator name for a hexpr using a fold map. *)
val hexpr_to_iexpr :
  inputs:Ast.ident list ->
  fold_map:(Ast.hexpr * Ast.ident) list ->
  var_types:(Ast.ident * Ast.ty) list ->
  pre_k_map:(Ast.hexpr * Support.pre_k_info) list ->
  Ast.hexpr -> Ast.iexpr option
(** Convert a hexpr to an iexpr when representable. *)
val infer_iexpr_type :
  var_types:(Ast.ident * Ast.ty) list -> Ast.iexpr -> Ast.ty option
(** Infer a simple type for an iexpr from variable types. *)
val mk_bool_eq : Ast.iexpr -> Ast.iexpr -> Ast.iexpr
(** Boolean equality encoded as a pure boolean expression. *)
val mk_bool_neq : Ast.iexpr -> Ast.iexpr -> Ast.iexpr
(** Boolean inequality encoded as a pure boolean expression. *)
val atom_to_iexpr :
  inputs:Ast.ident list ->
  var_types:(Ast.ident * Ast.ty) list ->
  fold_map:(Ast.hexpr * Ast.ident) list ->
  pre_k_map:(Ast.hexpr * Support.pre_k_info) list ->
  Ast.fo -> Ast.iexpr option
(** Convert an atomic FO predicate to an iexpr when possible. *)
val atom_to_var_rel : Ast.ident -> Ast.fo
(** Encode an atom variable as a FO relation (var = true). *)
val iexpr_to_fo_with_atoms : (Ast.ident * Ast.fo) list -> Ast.iexpr -> Ast.fo
(** Reconstruct FO by inlining atom variables from a name->atom map. *)
(** {1 Atom Replacement} *)

val replace_atoms_ltl : (Ast.fo * Ast.ident) list -> Ast.fo_ltl -> Ast.fo_ltl
(** Replace atom formulas by their variable representation in LTL. *)
val replace_atoms_fo : (Ast.fo * Ast.ident) list -> Ast.fo -> Ast.fo
(** Replace atom formulas by their variable representation in FO. *)
val replace_atoms_invariants_mon :
  (Ast.fo * Ast.ident) list ->
  Ast.invariant_mon list -> Ast.invariant_mon list
(** Replace atom formulas inside monitor invariants. *)
val replace_atoms_transition :
  (Ast.fo * Ast.ident) list -> Ast_contracts.transition -> Ast_contracts.transition
(** Replace atom formulas inside a transition. *)
(** {1 Fold Diagnostics} *)

val fold_map_for_node : Ast_contracts.node -> (Ast.hexpr * Ast.ident) list
(** Build a fold map for a node, for atom replacement purposes. *)
val fold_vars_in_iexpr : Ast.ident list -> Ast.iexpr -> Ast.ident list
(** Collect variable names used by an iexpr. *)
val fold_origin_suffix_for_expr :
  (Ast.hexpr * Ast.ident) list -> Ast.iexpr -> string
(** Human-readable fold origin suffix for an iexpr. *)
(** {1 Monitor Specs} *)

val combine_contracts_for_monitor :
  assumes:Ast.fo_ltl list -> guarantees:Ast.fo_ltl list -> Ast.fo_ltl
(** Combine assume/guarantee lists into a single monitor spec. *)
