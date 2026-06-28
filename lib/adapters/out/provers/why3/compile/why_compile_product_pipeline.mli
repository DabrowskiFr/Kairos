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

(** Product-step Why3 helper pipeline.

    This facade assembles the product-specific backend steps:
    contract fact selection, shared bundle construction, helper specs, helper
    planning, metrics, and final helper emission. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  runtime_view : Why_runtime_view.t;
  module_name : string;
  imports : Why3.Ptree.decl list;
  common_import : Why3.Ptree.decl;
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  share_why3_facts : bool;
  simplify_why3_formulas : bool;
  group_why3_product_steps : bool;
  why3_product_step_group_max_cost : int;
  simplify_why3_runtime_actions : bool;
  abstract_formula :
    in_post:bool -> Core_syntax.hexpr -> Why3.Ptree.term option;
  abstract_formula_with_rec :
    string -> Core_syntax.hexpr -> Why3.Ptree.term option;
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
}

type result = {
  shared_pre_bundle_modules : Why_compile_modules.module_unit list;
  shared_post_bundle_modules : Why_compile_modules.module_unit list;
  kernel_step_helper_units : Why_compile_helper_unit.t list;
}

val build : context -> Why_contracts.step_contract_info list -> result
