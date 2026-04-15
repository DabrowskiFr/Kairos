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

(** Metadata attached to one temporal-history source variable. *)
type pre_k_info = {
  var_name : Core_syntax.ident;
  names : string list;
  vty : Core_syntax.ty;
}
[@@deriving yojson]

(** [build_pre_k_infos_from_parts ~inputs ~locals ~outputs ~fo_formulas ~ltl]
    computes the [pre_k] layout for the given formula set.

    The result provides one {!type:pre_k_info} per source
    variable that appears under [pre_k], with slot names sized to the maximal
    required depth for that variable. *)
val build_pre_k_infos_from_parts :
  inputs:Core_syntax.vdecl list ->
  locals:Core_syntax.vdecl list ->
  outputs:Core_syntax.vdecl list ->
  fo_formulas:Core_syntax.hexpr list ->
  ltl:Core_syntax.ltl list ->
  pre_k_info list

(** [build_pre_k_infos node] is the node-level entry point used by the pipeline.

    It collects [pre_k] references from:
    {ul
    {- state invariants as first-order formulas;}
    {- [require]/[ensures] LTL clauses.}
    } *)
val build_pre_k_infos : Verification_model.node_model -> pre_k_info list
