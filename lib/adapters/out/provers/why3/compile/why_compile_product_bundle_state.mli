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

(** Product-specific state for shared bundle predicates.

    This module owns the mutable tables used to reuse generated bundle
    predicates. Product pipeline orchestration should not manipulate these
    tables directly. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  module_name : string;
  imports : Why3.Ptree.decl list;
  common_import : Why3.Ptree.decl;
  inputs : Why3.Ptree.binder list;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
}

type t

val create : context -> t

val predicate_bundle_decl_and_call :
  t -> name:string -> Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term

val shared_pre_bundle_call :
  t -> Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term * StringSet.t

val shared_post_bundle_call :
  t -> Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term * StringSet.t

val shared_pre_bundle_modules : t -> Why_compile_modules.module_unit list
val shared_post_bundle_modules : t -> Why_compile_modules.module_unit list
