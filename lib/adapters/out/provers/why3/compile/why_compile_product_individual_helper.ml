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

open Why3
open Ptree
open Why_compile_expr
open Why_compile_ptree_helpers
module Body = Why_compile_product_helper_body
module Product_groups = Why_compile_product_groups
module Product_specs = Why_compile_product_specs
module Step_names = Why_product_step_names
module Types = Why_compile_product_helper_types

let build (ctx : Types.context) (plan : Product_groups.individual_plan) :
    Types.helper_unit =
  let i = plan.index in
  let sc = plan.contract in
  let t = plan.transition in
  let helper_name =
    ident (Step_names.product_step_helper_name ~index:i sc.step)
  in
  let helper_contract =
    Product_specs.individual_helper_contract ctx.spec_context ~step_index:i
      ~helper_name:helper_name.Ptree.id_str sc
  in
  let helper_body = Body.individual_body ~env:ctx.env t ~local_cuts:sc.local_cuts in
  let local_shared_decls =
    helper_contract.direct_shared_terms
    |> ctx.shared_formula_names_in_terms
    |> ctx.local_shared_formula_decls
         ~exclude:helper_contract.imported_shared_names
  in
  let helper_inputs =
    helper_binders_without_unused_parameters ctx.inputs helper_contract.spec
      helper_body
  in
  let fn = Body.helper_function helper_inputs helper_contract.spec helper_body in
  {
    Types.helper_name = helper_name.Ptree.id_str;
    decls =
      helper_contract.post_decls @ local_shared_decls
      @ helper_contract.pre_imports
      @ [ Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ];
    pre_labels = helper_contract.pre_labels;
    post_labels = helper_contract.post_labels;
  }
