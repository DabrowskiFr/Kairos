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

(** Collection of [pre_k] usage and slot layout extraction.

    This module computes the temporal layout required by one node before lowering:
    it scans formulas, finds all [pre_k] occurrences, computes maximal depths per
    variable, and builds the corresponding slot metadata. *)

(** [build_pre_k_infos_from_parts ~inputs ~locals ~outputs ~fo_formulas ~ltl]
    computes the [pre_k] layout for the given formula set.

    The result maps each encountered [HPreK] source expression to one
    {!type:Temporal_support.pre_k_info} record containing generated slot names
    and type information. *)
val build_pre_k_infos_from_parts :
  inputs:Core_syntax.vdecl list ->
  locals:Core_syntax.vdecl list ->
  outputs:Core_syntax.vdecl list ->
  fo_formulas:Core_syntax.hexpr list ->
  ltl:Core_syntax.ltl list ->
  (Core_syntax.hexpr * Temporal_support.pre_k_info) list

(** [build_pre_k_infos node] is the node-level entry point used by the pipeline.

    It collects [pre_k] references from:
    {ul
    {- state invariants as first-order formulas;}
    {- [require]/[ensures] LTL clauses.}
    } *)
val build_pre_k_infos : Ast.node -> (Core_syntax.hexpr * Temporal_support.pre_k_info) list
