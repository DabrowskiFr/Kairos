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
  source_var : Kr_domain_core_syntax.ident;
  (** Candidate slot names used during lowering. *)
  slot_names : Kr_domain_core_syntax.ident list;
}

(** [temporal_bindings_of_layout ~temporal_layout] converts layout metadata into
    explicit lowering bindings. *)
val temporal_bindings_of_layout :
  temporal_layout:Kr_domain_core_history_layout.pre_k_info list -> temporal_binding list

(** [hexpr_to_expr ~inputs ~var_types ~temporal_layout h] attempts to translate
    [h] to an executable expression by replacing [HPreK] nodes with materialized
    slots. Unsupported constructs (notably [HPred]) return [None]. *)
val hexpr_to_expr :
  inputs:Kr_domain_core_syntax.ident list ->
  var_types:(Kr_domain_core_syntax.ident * Kr_domain_core_syntax.ty) list ->
  temporal_layout:Kr_domain_core_history_layout.pre_k_info list ->
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr ->
  Kr_domain_core_syntax.expr option

(** Lower one first-order formula (represented as [hexpr]) with explicit bindings. *)
val lower_fo_formula_temporal_bindings :
  temporal_bindings:temporal_binding list ->
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr ->
  Kr_domain_core_syntax.history_free Kr_domain_core_syntax.hexpr option
