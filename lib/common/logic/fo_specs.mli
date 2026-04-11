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

(** {1 Atom Collection}

    Utilities to extract atomic first-order formulas from specifications. *)

(** Collect atomic first-order formulas referenced by an LTL formula. *)
val collect_atoms_ltl : Core_syntax.ltl -> Core_syntax.fo_atom list -> Core_syntax.fo_atom list

(** Conjoin a list of first-order formulas, or return [None] for an empty
    list. *)
val conj_fo : Fo_formula.t list -> Fo_formula.t option

(** {1 Expression Conversion} *)

type temporal_binding = {
  source_hexpr : Core_syntax.hexpr;
  slot_names : Core_syntax.ident list;
}

val temporal_bindings_of_pre_k_map :
  pre_k_map:(Core_syntax.hexpr * Temporal_support.pre_k_info) list -> temporal_binding list

(** Convert a history expression to an immediate expression when representable,
    using temporal bindings. *)
val hexpr_to_iexpr_with_temporal_bindings :
  inputs:Core_syntax.ident list ->
  var_types:(Core_syntax.ident * Core_syntax.ty) list ->
  temporal_bindings:temporal_binding list ->
  Core_syntax.hexpr ->
  Core_syntax.iexpr option

val hexpr_to_iexpr :
  inputs:Core_syntax.ident list ->
  var_types:(Core_syntax.ident * Core_syntax.ty) list ->
  pre_k_map:(Core_syntax.hexpr * Temporal_support.pre_k_info) list ->
  Core_syntax.hexpr ->
  Core_syntax.iexpr option

(** Lower [pre_k] occurrences to explicit symbolic history variables. *)
val lower_hexpr_temporal_bindings :
  temporal_bindings:temporal_binding list -> Core_syntax.hexpr -> Core_syntax.hexpr option

val lower_hexpr_pre_k :
  pre_k_map:(Core_syntax.hexpr * Temporal_support.pre_k_info) list -> Core_syntax.hexpr -> Core_syntax.hexpr option

(** Lower [pre_k] occurrences inside a first-order formula. *)
val lower_fo_temporal_bindings :
  temporal_bindings:temporal_binding list -> Core_syntax.fo_atom -> Core_syntax.fo_atom option

val lower_fo_pre_k :
  pre_k_map:(Core_syntax.hexpr * Temporal_support.pre_k_info) list -> Core_syntax.fo_atom -> Core_syntax.fo_atom option

(** Lower [pre_k] occurrences inside a non-temporal first-order formula. *)
val lower_fo_formula_temporal_bindings :
  temporal_bindings:temporal_binding list -> Fo_formula.t -> Fo_formula.t option

val lower_fo_formula_pre_k :
  pre_k_map:(Core_syntax.hexpr * Temporal_support.pre_k_info) list -> Fo_formula.t -> Fo_formula.t option

(** Infer a simple type for an immediate expression from variable types. *)
val infer_iexpr_type : var_types:(Core_syntax.ident * Core_syntax.ty) list -> Core_syntax.iexpr -> Core_syntax.ty option

(** Boolean equality encoded as a pure boolean expression. *)
val mk_bool_eq : Core_syntax.iexpr -> Core_syntax.iexpr -> Core_syntax.iexpr

(** Boolean inequality encoded as a pure boolean expression. *)
val mk_bool_neq : Core_syntax.iexpr -> Core_syntax.iexpr -> Core_syntax.iexpr

(** Convert an atomic first-order predicate to an immediate expression when
    possible. *)
val atom_to_iexpr :
  inputs:Core_syntax.ident list ->
  var_types:(Core_syntax.ident * Core_syntax.ty) list ->
  pre_k_map:(Core_syntax.hexpr * Temporal_support.pre_k_info) list ->
  Core_syntax.fo_atom ->
  Core_syntax.iexpr option

(** Encode an atom variable as a first-order relation [var = true]. *)
val atom_to_var_rel : Core_syntax.ident -> Core_syntax.fo_atom

(** Reconstruct a non-temporal formula by inlining atom variables from a
    name-to-atom map. *)
val iexpr_to_fo_with_atoms : (Core_syntax.ident * Core_syntax.fo_atom) list -> Core_syntax.iexpr -> Fo_formula.t


(** {1 Instrumentation Specs} *)

(** Build the temporal specification used for guarantee automata.

    Current policy: only guarantees are turned into an automaton;
    assumptions are handled as proof hypotheses. *)
val combine_contracts_for_monitor :
  assumes:Core_syntax.ltl list -> guarantees:Core_syntax.ltl list -> Core_syntax.ltl
