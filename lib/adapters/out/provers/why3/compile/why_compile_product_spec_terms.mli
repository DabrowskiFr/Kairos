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

(** Term selection and sharing policy for individual product-step specs.

    This module decides which pre/post terms are kept directly, moved through
    shared bundle predicates, or hidden behind a post bundle. It does not build
    Why3 function specs. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  env : Why_compile_expr.env;
  pre_family_terms_by_step : Why3.Ptree.term list list;
  post_family_terms_by_step : Why3.Ptree.term list list;
  pre_family_bundle_counts : (string, int) Hashtbl.t;
  post_family_bundle_counts : (string, int) Hashtbl.t;
  predicate_bundle_decl_and_call :
    name:string -> Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term;
  shared_pre_bundle_call :
    Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term * StringSet.t;
  shared_post_bundle_call :
    Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term * StringSet.t;
}

type individual = {
  pre_decls : Why3.Ptree.decl list;
  post_decls : Why3.Ptree.decl list;
  pre_term : Why3.Ptree.term;
  post_terms : Why3.Ptree.term list;
  raw_pre_terms : Why3.Ptree.term list;
  raw_post_terms : Why3.Ptree.term list;
  bundle_post_terms : bool;
  imported_shared_names : StringSet.t;
  post_labels : string list;
}

val individual :
  context ->
  step_index:int ->
  helper_name:string ->
  Why_contracts.step_contract_info ->
  individual
