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
module Product_layout = Why_compile_product_layout
module Product_specs = Why_compile_product_specs
module Step_names = Why_product_step_names
module Types = Why_compile_product_helper_types

let build (ctx : Types.context) (plan : Product_groups.grouped_plan) :
    Types.helper_unit =
  let entries = plan.entries in
  let first_i, (first_sc : Why_contracts.step_contract_info), first_t =
    List.hd entries
  in
  let helper_name =
    ident
      (Step_names.product_step_group_helper_name ~index:first_i first_sc.step)
  in
  let post_pred_name = helper_name.Ptree.id_str ^ "_post" in
  let grouped_contract =
    Product_specs.grouped_helper_contract ~env:ctx.env ~inputs:ctx.inputs
      ~pre_vars_name:Product_layout.pre_vars_name
      ~post_vars_name:Product_layout.post_vars_name ~post_pred_name
      plan.grouped_terms
  in
  let local_shared_decls =
    grouped_contract.shared_terms
    |> ctx.shared_formula_names_in_terms
    |> ctx.local_shared_formula_decls
  in
  let helper_body =
    Body.grouped_body ~env:ctx.env first_t
      ~post_call:grouped_contract.post_call
  in
  let helper_inputs =
    helper_binders_without_unused_parameters ctx.inputs grouped_contract.spec
      helper_body
  in
  let fn = Body.helper_function helper_inputs grouped_contract.spec helper_body in
  {
    Types.helper_name = helper_name.Ptree.id_str;
    decls =
      local_shared_decls
      @ [
          grouped_contract.post_pred_decl;
          Ptree.Dlet (helper_name, false, Expr.RKnone, fn);
        ];
    pre_labels = grouped_contract.pre_labels;
    post_labels = grouped_contract.post_labels;
  }
