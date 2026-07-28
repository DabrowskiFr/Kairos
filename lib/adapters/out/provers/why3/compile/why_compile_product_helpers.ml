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


(** Emit individual or grouped WhyML helpers from one product-step plan. *)

module Product_specs = Why_compile_product_specs
module Step_names = Why_product_step_names

type helper_unit = {
  helper_name : string;
  decls : Why3.Ptree.decl list;
}

type context = {
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  formula_sharing : Why_compile_formula_sharing.t;
  formula_imports : Core_syntax.history_free Ir.summary_formula list -> Why3.Ptree.decl list;
  bundles : Why_compile_bundles.t;
}

open Why3
open Ptree
open Why_compile_expr
open Why_compile_ptree_helpers

let helper_function helper_inputs spc helper_body =
  mk_expr
    (Efun
       ( helper_inputs,
         None,
         { pat_desc = Pwild; pat_loc = loc },
         Ity.MaskVisible,
         spc,
         helper_body ))

let grouped_body ~env transition ~post_call =
  let pre_snapshot_name = "__pre_snapshot" in
  let snapshot_expr =
    env.rec_vars
    |> List.map (fun field_name -> (qid1 field_name, field env field_name))
    |> fun fields -> mk_expr (Erecord fields)
  in
  let proof_assert =
    mk_expr (Eassert (Expr.Assert, post_call ~pre_snapshot_name))
  in
  let body =
    seq_exprs
      [
        Why_compile_step.compile_transition_body env transition;
        proof_assert;
      ]
  in
  mk_expr
    (Elet (ident pre_snapshot_name, true, Expr.RKnone, snapshot_expr, body))

let build_individual (ctx : context) (plan : Proof_plan.individual) :
    helper_unit =
  let i = plan.index in
  let sc = plan.member.contract in
  let helper_name =
    ident (Step_names.product_step_helper_name ~index:i sc)
  in
  let helper_contract =
    Product_specs.individual_helper_contract ~env:ctx.env ~inputs:ctx.inputs
      ~formula_sharing:ctx.formula_sharing
      ~formula_imports:ctx.formula_imports
      ~helper_name:helper_name.Ptree.id_str
      ~bundles:ctx.bundles plan
  in
  let helper_body, body_inputs =
    collect_used_inputs ctx.env (fun env ->
        Why_compile_step.compile_transition_body env sc.program_step)
  in
  let helper_inputs =
    binders_used_by
      (StringSet.union helper_contract.used_inputs body_inputs)
      ctx.inputs
  in
  let fn = helper_function helper_inputs helper_contract.spec helper_body in
  {
    helper_name = helper_name.Ptree.id_str;
    decls =
      helper_contract.decls
      @ [ Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ];
  }

let build_grouped (ctx : context) (plan : Proof_plan.grouped) :
    helper_unit =
  let first_i = plan.index in
  let first_sc = plan.representative.contract in
  let helper_name =
    ident
      (Step_names.product_step_group_helper_name ~index:first_i first_sc)
  in
  let post_pred_name = helper_name.Ptree.id_str ^ "_post" in
  let grouped_contract =
    Product_specs.grouped_helper_contract ~env:ctx.env ~inputs:ctx.inputs
      ~formula_sharing:ctx.formula_sharing
      ~formula_imports:ctx.formula_imports ~post_pred_name plan
  in
  let helper_body, body_inputs =
    collect_used_inputs ctx.env (fun env ->
        grouped_body ~env first_sc.program_step
          ~post_call:grouped_contract.post_call)
  in
  let helper_inputs =
    binders_used_by
      (StringSet.union grouped_contract.used_inputs body_inputs)
      ctx.inputs
  in
  let fn = helper_function helper_inputs grouped_contract.spec helper_body in
  {
    helper_name = helper_name.Ptree.id_str;
    decls =
      grouped_contract.decls
      @ [ Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ];
  }

let kernel_step_helper_units ~env ~inputs ~formula_sharing ~formula_imports
    ~bundles plan =
  let ctx =
    { env; inputs; formula_sharing; formula_imports; bundles }
  in
  plan
  |> List.map (function
       | Proof_plan.Individual individual ->
           build_individual ctx individual
       | Proof_plan.Grouped grouped -> build_grouped ctx grouped)
