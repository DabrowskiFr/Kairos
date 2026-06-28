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

module Bundle_state = Why_compile_product_bundle_state
module Contract_facts = Why_compile_contract_facts
module Modules = Why_compile_modules
module Product_helpers = Why_compile_product_helpers
module Product_plan = Why_compile_product_plan
module Product_plan_metrics = Why_compile_product_plan_metrics
module Product_specs = Why_compile_product_specs
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
  shared_pre_bundle_modules : Modules.module_unit list;
  shared_post_bundle_modules : Modules.module_unit list;
  kernel_step_helper_units : Why_compile_helper_unit.t list;
}

let build ctx step_contracts =
  let bundle_state =
    Bundle_state.create
      {
        module_name = ctx.module_name;
        imports = ctx.imports;
        common_import = ctx.common_import;
        inputs = ctx.inputs;
        local_shared_formula_decls = ctx.local_shared_formula_decls;
        shared_formula_names_in_terms = ctx.shared_formula_names_in_terms;
      }
  in
  let contract_fact_context : Contract_facts.context =
    {
      env = ctx.env;
      simplify_why3_formulas = ctx.simplify_why3_formulas;
      abstract_formula = ctx.abstract_formula;
      abstract_formula_with_rec = ctx.abstract_formula_with_rec;
    }
  in
  let product_helper_facts =
    Contract_facts.product_helper_facts contract_fact_context
      ~share_why3_facts:ctx.share_why3_facts step_contracts
  in
  let product_spec_context : Product_specs.context =
    {
      env = ctx.env;
      pre_family_terms_by_step = product_helper_facts.pre_family_terms_by_step;
      post_family_terms_by_step =
        product_helper_facts.post_family_terms_by_step;
      pre_family_bundle_counts = product_helper_facts.pre_family_bundle_counts;
      post_family_bundle_counts =
        product_helper_facts.post_family_bundle_counts;
      predicate_bundle_decl_and_call =
        Bundle_state.predicate_bundle_decl_and_call bundle_state;
      shared_pre_bundle_call = Bundle_state.shared_pre_bundle_call bundle_state;
      shared_post_bundle_call =
        Bundle_state.shared_post_bundle_call bundle_state;
    }
  in
  let product_helper_context : Product_helpers.context =
    {
      env = ctx.env;
      inputs = ctx.inputs;
      spec_context = product_spec_context;
      shared_formula_names_in_terms = ctx.shared_formula_names_in_terms;
      local_shared_formula_decls = ctx.local_shared_formula_decls;
    }
  in
  let product_plan_context : Product_plan.context =
    {
      env = ctx.env;
      group_why3_product_steps = ctx.group_why3_product_steps;
      why3_product_step_group_max_cost =
        ctx.why3_product_step_group_max_cost;
      simplify_why3_runtime_actions = ctx.simplify_why3_runtime_actions;
    }
  in
  let product_helper_plan =
    Product_plan.build product_plan_context product_helper_facts step_contracts
  in
  Product_plan_metrics.observe
    {
      node_name = ctx.runtime_view.node_name;
      max_cost = ctx.why3_product_step_group_max_cost;
    }
    product_helper_plan;
  {
    shared_pre_bundle_modules =
      Bundle_state.shared_pre_bundle_modules bundle_state;
    shared_post_bundle_modules =
      Bundle_state.shared_post_bundle_modules bundle_state;
    kernel_step_helper_units =
      Product_helpers.kernel_step_helper_units product_helper_context
        product_helper_plan;
  }
