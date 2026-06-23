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
module Product_groups = Why_compile_product_groups
module Product_layout = Why_compile_product_layout
module Product_specs = Why_compile_product_specs
module Step_names = Why_compile_step_names
module StringSet = Why_compile_ptree_helpers.StringSet

type helper_unit = {
  helper_name : string;
  decls : Ptree.decl list;
  pre_labels : string list;
  post_labels : string list;
}

type context = {
  env : Why_compile_expr.env;
  inputs : Ptree.binder list;
  spec_context : Product_specs.context;
  shared_formula_names_in_terms : Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Ptree.decl list;
}

let seq_exprs (exprs : Ptree.expr list) =
  let exprs =
    List.filter
      (fun expr -> match expr.expr_desc with Etuple [] -> false | _ -> true)
      exprs
  in
  match exprs with
  | [] -> mk_expr (Etuple [])
  | first :: rest ->
      List.fold_left
        (fun acc expr -> mk_expr (Esequence (acc, expr)))
        first rest

let helper_function helper_inputs spc helper_body =
  mk_expr
    (Efun
       ( helper_inputs,
         None,
         { pat_desc = Pwild; pat_loc = loc },
         Ity.MaskVisible,
         spc,
         helper_body ))

let build_individual_kernel_helper ctx
    (plan : Product_groups.individual_plan) =
  let i = plan.index in
  let sc = plan.contract in
  let t = plan.transition in
  let helper_name =
    ident (Step_names.product_step_helper_name ~index:i sc.step)
  in
  let helper_contract =
    Product_specs.individual_helper_contract
      ctx.spec_context
      ~step_index:i ~helper_name:helper_name.Ptree.id_str sc
  in
  let local_cut_asserts =
    sc.local_cuts
    |> List.map (fun term -> mk_expr (Eassert (Expr.Assert, term)))
  in
  let helper_body =
    seq_exprs
      (Why_compile_step.compile_transition_body ctx.env [] t
      :: local_cut_asserts)
  in
  let direct_shared_terms =
    helper_contract.direct_shared_terms
  in
  let local_shared_decls =
    direct_shared_terms |> ctx.shared_formula_names_in_terms
    |> ctx.local_shared_formula_decls
         ~exclude:helper_contract.imported_shared_names
  in
  let helper_inputs =
    helper_binders_without_unused_parameters ctx.inputs helper_contract.spec
      helper_body
  in
  let fn = helper_function helper_inputs helper_contract.spec helper_body in
  {
    helper_name = helper_name.Ptree.id_str;
    decls =
      helper_contract.post_decls @ local_shared_decls
      @ helper_contract.pre_imports
      @ [ Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ];
    pre_labels = helper_contract.pre_labels;
    post_labels = helper_contract.post_labels;
  }

let build_grouped_kernel_helper ctx (plan : Product_groups.grouped_plan) =
  let entries = plan.entries in
  let first_i, (first_sc : Why_contracts.step_contract_info), first_t =
    List.hd entries
  in
  let helper_name =
    ident
      (Step_names.product_step_group_helper_name ~index:first_i first_sc.step)
  in
  let post_pred_name = helper_name.Ptree.id_str ^ "_post" in
  let grouped = plan.grouped_terms in
  let grouped_contract =
    Product_specs.grouped_helper_contract ~env:ctx.env ~inputs:ctx.inputs
      ~pre_vars_name:Product_layout.pre_vars_name
      ~post_vars_name:Product_layout.post_vars_name ~post_pred_name grouped
  in
  let local_shared_decls =
    grouped_contract.shared_terms
    |> ctx.shared_formula_names_in_terms |> ctx.local_shared_formula_decls
  in
  let pre_snapshot_name = "__pre_snapshot" in
  let snapshot_expr =
    ctx.env.rec_vars
    |> List.map (fun field_name -> (qid1 field_name, field ctx.env field_name))
    |> fun fields -> mk_expr (Erecord fields)
  in
  let helper_body =
    let proof_assert =
      mk_expr
        (Eassert
           ( Expr.Assert,
             grouped_contract.post_call ~pre_snapshot_name ))
    in
    let body =
      seq_exprs
        [
          Why_compile_step.compile_transition_body ctx.env [] first_t;
          proof_assert;
        ]
    in
    mk_expr
      (Elet (ident pre_snapshot_name, true, Expr.RKnone, snapshot_expr, body))
  in
  let helper_inputs =
    helper_binders_without_unused_parameters ctx.inputs grouped_contract.spec
      helper_body
  in
  let fn = helper_function helper_inputs grouped_contract.spec helper_body in
  {
    helper_name = helper_name.Ptree.id_str;
    decls =
      local_shared_decls
      @ [
          grouped_contract.post_pred_decl;
          Ptree.Dlet (helper_name, false, Expr.RKnone, fn);
        ];
    pre_labels = grouped_contract.pre_labels;
    post_labels = grouped_contract.post_labels;
  }

let kernel_step_helper_units ctx plan =
  plan
  |> List.map (function
       | Product_groups.Individual individual ->
           build_individual_kernel_helper ctx individual
       | Product_groups.Grouped grouped -> build_grouped_kernel_helper ctx grouped)
