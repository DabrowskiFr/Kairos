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

module Contract_facts = Why_compile_contract_facts
module Product_groups = Why_compile_product_groups
module Product_layout = Why_compile_product_layout
module Product_metrics = Why_compile_product_metrics

type context = {
  runtime_view : Why_runtime_view.t;
  env : Why_compile_expr.env;
  group_why3_product_steps : bool;
  why3_product_step_group_max_cost : int;
  simplify_why3_runtime_actions : bool;
}

let build ctx (facts : Contract_facts.product_helper_facts) step_contracts =
  let plan =
    Product_groups.plan_kernel_helpers ~env:ctx.env
      ~pre_vars_name:Product_layout.pre_vars_name
      ~post_vars_name:Product_layout.post_vars_name
      ~group_why3_product_steps:ctx.group_why3_product_steps
      ~max_cost:ctx.why3_product_step_group_max_cost
      ~simplify_runtime_actions:ctx.simplify_why3_runtime_actions
      ~step_pre_terms_with_rec:facts.step_pre_terms_with_rec
      ~step_post_terms_with_rec:facts.step_post_terms_with_rec step_contracts
  in
  Product_metrics.record_plan
    {
      node_name = ctx.runtime_view.node_name;
      max_cost = ctx.why3_product_step_group_max_cost;
    }
    plan;
  plan
