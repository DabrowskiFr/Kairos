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

(** Concrete Why3 emission for product-step proof helpers. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type helper_unit = {
  helper_name : string;
  decls : Why3.Ptree.decl list;
  pre_labels : string list;
  post_labels : string list;
}

type context = {
  runtime_view : Why_runtime_view.t;
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
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
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
  step_pre_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Why3.Ptree.term list;
  step_post_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Why3.Ptree.term list;
  group_why3_product_steps : bool;
  why3_product_step_group_max_cost : int;
  simplify_why3_runtime_actions : bool;
}

val kernel_step_helper_units :
  context -> Why_contracts.step_contract_info list -> helper_unit list
