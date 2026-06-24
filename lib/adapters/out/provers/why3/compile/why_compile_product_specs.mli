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

(** Product-step helper specifications.

    This module builds concrete Why3 pre/post specs from already-selected
    terms. Term sharing policy and presentation labels live in focused sibling
    modules. Helper emission remains responsible for function bodies and
    declarations. *)

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

type individual_contract = {
  pre_imports : Why3.Ptree.decl list;
  post_decls : Why3.Ptree.decl list;
  spec : Why3.Ptree.spec;
  direct_shared_terms : Why3.Ptree.term list;
  imported_shared_names : StringSet.t;
  pre_labels : string list;
  post_labels : string list;
}

type grouped_contract = {
  post_pred_decl : Why3.Ptree.decl;
  spec : Why3.Ptree.spec;
  shared_terms : Why3.Ptree.term list;
  post_call : pre_snapshot_name:string -> Why3.Ptree.term;
  pre_labels : string list;
  post_labels : string list;
}

val individual_helper_contract :
  context ->
  step_index:int ->
  helper_name:string ->
  Why_contracts.step_contract_info ->
  individual_contract

val grouped_helper_contract :
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  pre_vars_name:string ->
  post_vars_name:string ->
  post_pred_name:string ->
  Why_compile_product_group_boundary.proof_terms ->
  grouped_contract
