(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Bundling of repeated Why3 pre/post terms into auxiliary predicates. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type 'groups module_unit =
  Why3.Ptree.ident * Why3.Ptree.qualid option * Why3.Ptree.decl list * 'groups

type 'groups context = {
  module_name : string;
  imports : Why3.Ptree.decl list;
  common_import : Why3.Ptree.decl;
  inputs : Why3.Ptree.binder list;
  empty_groups : unit -> 'groups;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
}

val predicate_bundle_decl_and_call :
  inputs:Why3.Ptree.binder list ->
  name:string ->
  Why3.Ptree.term list ->
  Why3.Ptree.decl * Why3.Ptree.term

val shared_bundle_call :
  context:'groups context ->
  module_suffix:string ->
  predicate_prefix:string ->
  table:(string, string * string) Hashtbl.t ->
  modules:'groups module_unit list ref ->
  Why3.Ptree.term list ->
  Why3.Ptree.decl * Why3.Ptree.term * StringSet.t

val bundle_key : Why3.Ptree.term list -> string
val remove_terms : Why3.Ptree.term list -> Why3.Ptree.term list -> Why3.Ptree.term list
val count_bundles : Why3.Ptree.term list list -> (string, int) Hashtbl.t
val should_share_bundle : (string, int) Hashtbl.t -> Why3.Ptree.term list -> bool
