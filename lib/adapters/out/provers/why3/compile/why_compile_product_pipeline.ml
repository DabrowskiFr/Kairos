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

module Bundles = Why_compile_bundles
module Contract_facts = Why_compile_contract_facts
module Modules = Why_compile_modules
module Product_groups = Why_compile_product_groups
module Product_helpers = Why_compile_product_helpers
module Product_layout = Why_compile_product_layout
module Product_metrics = Why_compile_product_metrics
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
  kernel_step_helper_units : Product_helpers.helper_unit list;
}

let build_bundle_calls ctx =
  let bundle_context : Modules.spec_groups Bundles.context =
    {
      module_name = ctx.module_name;
      imports = ctx.imports;
      common_import = ctx.common_import;
      inputs = ctx.inputs;
      empty_groups = Modules.empty_groups;
      local_shared_formula_decls = ctx.local_shared_formula_decls;
      shared_formula_names_in_terms = ctx.shared_formula_names_in_terms;
    }
  in
  let shared_bundle_call = Bundles.shared_bundle_call ~context:bundle_context in
  let shared_post_bundle_table : (string, string * string) Hashtbl.t =
    Hashtbl.create 128
  in
  let shared_post_bundle_modules = ref [] in
  let shared_post_bundle_call =
    shared_bundle_call ~module_suffix:"Post"
      ~predicate_prefix:"shared_post_bundle" ~table:shared_post_bundle_table
      ~modules:shared_post_bundle_modules
  in
  let shared_pre_bundle_table : (string, string * string) Hashtbl.t =
    Hashtbl.create 128
  in
  let shared_pre_bundle_modules = ref [] in
  let shared_pre_bundle_call =
    shared_bundle_call ~module_suffix:"Pre"
      ~predicate_prefix:"shared_pre_bundle" ~table:shared_pre_bundle_table
      ~modules:shared_pre_bundle_modules
  in
  ( shared_pre_bundle_modules,
    shared_pre_bundle_call,
    shared_post_bundle_modules,
    shared_post_bundle_call )

let build ctx step_contracts =
  let ( shared_pre_bundle_modules,
        shared_pre_bundle_call,
        shared_post_bundle_modules,
        shared_post_bundle_call ) =
    build_bundle_calls ctx
  in
  let predicate_bundle_decl_and_call =
    Bundles.predicate_bundle_decl_and_call ~inputs:ctx.inputs
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
      predicate_bundle_decl_and_call;
      shared_pre_bundle_call;
      shared_post_bundle_call;
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
  let product_helper_plan =
    Product_groups.plan_kernel_helpers ~env:ctx.env
      ~pre_vars_name:Product_layout.pre_vars_name
      ~post_vars_name:Product_layout.post_vars_name
      ~group_why3_product_steps:ctx.group_why3_product_steps
      ~max_cost:ctx.why3_product_step_group_max_cost
      ~simplify_runtime_actions:ctx.simplify_why3_runtime_actions
      ~step_pre_terms_with_rec:product_helper_facts.step_pre_terms_with_rec
      ~step_post_terms_with_rec:product_helper_facts.step_post_terms_with_rec
      step_contracts
  in
  Product_metrics.record_plan
    {
      node_name = ctx.runtime_view.node_name;
      max_cost = ctx.why3_product_step_group_max_cost;
    }
    product_helper_plan;
  {
    shared_pre_bundle_modules = List.rev !shared_pre_bundle_modules;
    shared_post_bundle_modules = List.rev !shared_post_bundle_modules;
    kernel_step_helper_units =
      Product_helpers.kernel_step_helper_units product_helper_context
        product_helper_plan;
  }
