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

(** Lowering utilities from historical formulas to materialized temporal slots.

    A lowering map is provided either directly as a [temporal_layout] (layout
    result) or as explicit {!type:temporal_binding} values. Functions return [None] when
    some [pre_k] occurrence cannot be resolved to a slot. *)

(** Binding between a source variable and concrete slot names. *)
type temporal_binding = {
  (** Source variable for [pre_k(var, k)] lookups. *)
  source_var : Core_syntax.ident;
  (** Candidate slot names used during lowering. *)
  slot_names : Core_syntax.ident list;
}

(** [temporal_bindings_of_layout ~temporal_layout] converts layout metadata into
    explicit lowering bindings. *)
val temporal_bindings_of_layout :
  temporal_layout:Temporal_support.pre_k_info list -> temporal_binding list

(** [hexpr_to_expr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings h]
    attempts to translate [h] to an executable expression.

    - [HPreK] nodes are replaced by bound slots.
    - Unsupported constructs (notably [HPred]) return [None]. *)
val hexpr_to_expr_with_temporal_bindings :
  inputs:Core_syntax.ident list ->
  var_types:(Core_syntax.ident * Core_syntax.ty) list ->
  temporal_bindings:temporal_binding list ->
  Core_syntax.hexpr ->
  Core_syntax.expr option

(** Convenience wrapper around {!val:hexpr_to_expr_with_temporal_bindings}
    using [temporal_layout]-derived bindings. *)
val hexpr_to_expr :
  inputs:Core_syntax.ident list ->
  var_types:(Core_syntax.ident * Core_syntax.ty) list ->
  temporal_layout:Temporal_support.pre_k_info list ->
  Core_syntax.hexpr ->
  Core_syntax.expr option

(** [lower_hexpr_temporal_bindings ~temporal_bindings h] rewrites [h] by replacing
    [pre_k]-style nodes with slot variables. *)
val lower_hexpr_temporal_bindings : temporal_bindings:temporal_binding list -> Core_syntax.hexpr -> Core_syntax.hexpr option

(** Convenience wrapper around {!val:lower_hexpr_temporal_bindings} using
    [temporal_layout]-derived bindings. *)
val lower_hexpr_pre_k :
  temporal_layout:Temporal_support.pre_k_info list ->
  Core_syntax.hexpr ->
  Core_syntax.hexpr option

(** Lower one first-order formula (represented as [hexpr]) with explicit bindings. *)
val lower_fo_formula_temporal_bindings :
  temporal_bindings:temporal_binding list -> Core_syntax.hexpr -> Core_syntax.hexpr option

(** Convenience wrapper around {!val:lower_fo_formula_temporal_bindings}. *)
val lower_fo_formula_pre_k :
  temporal_layout:Temporal_support.pre_k_info list ->
  Core_syntax.hexpr ->
  Core_syntax.hexpr option
