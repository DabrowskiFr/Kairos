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
  runtime_view : Why_runtime_view.t;
  env : Why_compile_expr.env;
  inputs : Ptree.binder list;
  spec_context : Product_specs.context;
  shared_formula_names_in_terms : Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Ptree.decl list;
  step_pre_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Ptree.term list;
  step_post_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Ptree.term list;
  group_why3_product_steps : bool;
  why3_product_step_group_max_cost : int;
  simplify_why3_runtime_actions : bool;
}

let pre_vars_name = "__pre_vars"
let post_vars_name = "__post_vars"
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

let record_group_metrics ctx ~group_name ~emitted_as_group ~split_due_to_cost
    ~entries ~distinct_pre_count ~distinct_post_count ~post_implication_count
    ~pre_text_bytes ~post_text_bytes ~estimated_cost =
  let _first_i, (first_sc : Why_contracts.step_contract_info), _first_t =
    List.hd entries
  in
  External_timing.record_why3_product_group
    {
      group_name;
      node_name = ctx.runtime_view.node_name;
      transition_id = first_sc.step.transition_id;
      step_class = Step_names.product_step_class_name first_sc.step.step_class;
      source_state = Step_names.product_source_label first_sc.step.product_src;
      emitted_as_group;
      split_due_to_cost;
      edge_count = List.length entries;
      distinct_pre_count;
      distinct_post_count;
      post_implication_count;
      pre_text_bytes;
      post_text_bytes;
      estimated_cost;
      max_cost = ctx.why3_product_step_group_max_cost;
    }

let record_grouped_terms_metrics ctx ~group_name ~emitted_as_group
    ~split_due_to_cost ~entries
    (grouped : Product_groups.grouped_terms) =
  record_group_metrics ctx ~group_name ~emitted_as_group ~split_due_to_cost
    ~entries ~distinct_pre_count:grouped.distinct_pre_count
    ~distinct_post_count:grouped.distinct_post_count
    ~post_implication_count:grouped.post_implication_count
    ~pre_text_bytes:grouped.pre_text_bytes
    ~post_text_bytes:grouped.post_text_bytes ~estimated_cost:grouped.estimated_cost

let build_individual_kernel_helper ctx
    (plan : Product_groups.individual_plan) =
  let i = plan.index in
  let sc = plan.contract in
  let t = plan.transition in
  Option.iter
    (fun (metrics : Product_groups.group_metrics) ->
      record_grouped_terms_metrics ctx
        ~group_name:(Step_names.product_step_helper_name ~index:i sc.step)
        ~emitted_as_group:false
        ~split_due_to_cost:metrics.split_due_to_cost ~entries:[ (i, sc, t) ]
        metrics.grouped_terms)
    plan.split_metrics;
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
  record_grouped_terms_metrics ctx ~group_name:helper_name.Ptree.id_str
    ~emitted_as_group:true ~split_due_to_cost:plan.split_due_to_cost ~entries
    grouped;
  let grouped_contract =
    Product_specs.grouped_helper_contract ~env:ctx.env ~inputs:ctx.inputs
      ~pre_vars_name ~post_vars_name ~post_pred_name grouped
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

let kernel_step_helper_units ctx step_contracts =
  let plan =
    Product_groups.plan_kernel_helpers ~env:ctx.env ~pre_vars_name
    ~post_vars_name ~group_why3_product_steps:ctx.group_why3_product_steps
    ~max_cost:ctx.why3_product_step_group_max_cost
    ~simplify_runtime_actions:ctx.simplify_why3_runtime_actions
    ~step_pre_terms_with_rec:ctx.step_pre_terms_with_rec
    ~step_post_terms_with_rec:ctx.step_post_terms_with_rec
    step_contracts
  in
  plan
  |> List.map (function
       | Product_groups.Individual individual ->
           build_individual_kernel_helper ctx individual
       | Product_groups.Grouped grouped -> build_grouped_kernel_helper ctx grouped)
