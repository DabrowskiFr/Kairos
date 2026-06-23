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
module Bundles = Why_compile_bundles
module Product_groups = Why_compile_product_groups
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
  pre_family_terms_by_step : Ptree.term list list;
  post_family_terms_by_step : Ptree.term list list;
  pre_family_bundle_counts : (string, int) Hashtbl.t;
  post_family_bundle_counts : (string, int) Hashtbl.t;
  predicate_bundle_decl_and_call :
    name:string -> Ptree.term list -> Ptree.decl * Ptree.term;
  shared_pre_bundle_call :
    Ptree.term list -> Ptree.decl * Ptree.term * StringSet.t;
  shared_post_bundle_call :
    Ptree.term list -> Ptree.decl * Ptree.term * StringSet.t;
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
let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ])

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

let predicate_param_of_name name =
  (loc, Some (ident name), false, Ptree.PTtyapp (qid1 "vars", []))

let remove_labeled_terms terms labels removed =
  let removed_keys = List.map string_of_term removed in
  List.combine terms labels
  |> List.filter (fun (term, _label) ->
      not (List.mem (string_of_term term) removed_keys))
  |> List.split

let repeated_label label terms = List.map (fun _ -> label) terms

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

let build_individual_kernel_helper ctx
    (i, (sc : Why_contracts.step_contract_info)) =
  let t =
    Why_runtime_view.transition_of_product_step
      ~simplify_runtime_actions:ctx.simplify_why3_runtime_actions sc.step
  in
  let helper_name =
    ident (Step_names.product_step_helper_name ~index:i sc.step)
  in
  let state_guard =
    term_eq (term_of_var ctx.env "st") (mk_term (Tident (qid1 t.src_state)))
  in
  let pre_family_terms =
    Option.value ~default:[] (List.nth_opt ctx.pre_family_terms_by_step i)
  in
  let share_pre_family_bundle =
    Bundles.should_share_bundle ctx.pre_family_bundle_counts pre_family_terms
  in
  let pre_terms =
    if share_pre_family_bundle then Bundles.remove_terms pre_family_terms sc.pre
    else sc.pre
  in
  let pre_family_imports, pre_family_terms =
    if share_pre_family_bundle then
      let import_, call, _shared_names =
        ctx.shared_pre_bundle_call pre_family_terms
      in
      ([ import_ ], [ call ])
    else ([], [])
  in
  let post_family_terms =
    Option.value ~default:[] (List.nth_opt ctx.post_family_terms_by_step i)
  in
  let share_post_family_bundle =
    Bundles.should_share_bundle ctx.post_family_bundle_counts post_family_terms
    && not (List.exists term_has_old post_family_terms)
  in
  let post_terms =
    if share_post_family_bundle then
      Bundles.remove_terms post_family_terms sc.post
    else sc.post
  in
  let post_terms, post_labels =
    if share_post_family_bundle then
      remove_labeled_terms sc.post sc.post_labels post_family_terms
    else (post_terms, sc.post_labels)
  in
  let post_family_imports, post_family_terms, post_family_shared_names =
    if share_post_family_bundle then
      let import_, call, shared_names =
        ctx.shared_post_bundle_call post_family_terms
      in
      ([ import_ ], [ call ], shared_names)
    else ([], [], StringSet.empty)
  in
  let raw_pre_terms = state_guard :: (pre_family_terms @ pre_terms) in
  let raw_post_terms = sc.forbidden @ post_family_terms @ post_terms in
  let raw_post_labels =
    sc.forbidden_labels
    @ repeated_label "Shared postcondition facts" post_family_terms
    @ post_labels
  in
  let bundle_post_terms =
    List.length raw_post_terms > 1
    && not (List.exists term_has_old raw_post_terms)
  in
  let pre_bundle_decls, pre_term =
    let pre_decl, call =
      ctx.predicate_bundle_decl_and_call
        ~name:(helper_name.Ptree.id_str ^ "_pre")
        raw_pre_terms
    in
    ([ pre_decl ], call)
  in
  let post_bundle_decls, post_terms, imported_shared_names =
    if not bundle_post_terms then
      (post_family_imports, raw_post_terms, post_family_shared_names)
    else
      let post_import, call, shared_names =
        ctx.shared_post_bundle_call raw_post_terms
      in
      ( post_family_imports @ [ post_import ],
        [ call ],
        StringSet.union post_family_shared_names shared_names )
  in
  let spc =
    {
      Ptree.sp_pre = [ pre_term ];
      sp_post = List.rev_map mk_post post_terms;
      sp_xpost = [];
      sp_reads = [];
      sp_writes = [];
      sp_alias = [];
      sp_variant = [];
      sp_checkrw = false;
      sp_diverge = false;
      sp_partial = false;
    }
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
    raw_pre_terms
    @ (if bundle_post_terms then [] else raw_post_terms)
    @ sc.local_cuts
  in
  let local_shared_decls =
    direct_shared_terms |> ctx.shared_formula_names_in_terms
    |> ctx.local_shared_formula_decls ~exclude:imported_shared_names
  in
  let helper_inputs =
    helper_binders_without_unused_parameters ctx.inputs spc helper_body
  in
  let fn = helper_function helper_inputs spc helper_body in
  {
    helper_name = helper_name.Ptree.id_str;
    decls =
      post_bundle_decls @ local_shared_decls @ pre_family_imports
      @ pre_bundle_decls
      @ [ Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ];
    pre_labels = [ "Product step preconditions" ];
    post_labels =
      (if bundle_post_terms && raw_post_terms <> [] then
         [ "Product step postconditions" ]
       else raw_post_labels);
  }

let build_grouped_kernel_helper ctx ~split_due_to_cost entries =
  let first_i, (first_sc : Why_contracts.step_contract_info), first_t =
    List.hd entries
  in
  let helper_name =
    ident
      (Step_names.product_step_group_helper_name ~index:first_i first_sc.step)
  in
  let post_pred_name = helper_name.Ptree.id_str ^ "_post" in
  let grouped =
    Product_groups.grouped_kernel_terms ~env:ctx.env ~pre_vars_name
      ~post_vars_name ~step_pre_terms_with_rec:ctx.step_pre_terms_with_rec
      ~step_post_terms_with_rec:ctx.step_post_terms_with_rec entries
  in
  record_group_metrics ctx ~group_name:helper_name.Ptree.id_str
    ~emitted_as_group:true ~split_due_to_cost ~entries
    ~distinct_pre_count:grouped.distinct_pre_count
    ~distinct_post_count:grouped.distinct_post_count
    ~post_implication_count:grouped.post_implication_count
    ~pre_text_bytes:grouped.pre_text_bytes
    ~post_text_bytes:grouped.post_text_bytes
    ~estimated_cost:grouped.estimated_cost;
  let local_shared_decls =
    [ grouped.pre_term; grouped.post_body ]
    |> ctx.shared_formula_names_in_terms |> ctx.local_shared_formula_decls
  in
  let post_used_names = names_of_term grouped.post_body StringSet.empty in
  let input_binders_without_vars =
    match ctx.inputs with _vars :: rest -> rest | [] -> []
  in
  let post_input_binders =
    input_binders_without_vars
    |> List.filter (fun (_, id_opt, _, _) ->
        match id_opt with
        | None -> true
        | Some id -> StringSet.mem id.Ptree.id_str post_used_names)
  in
  let post_pred_params =
    [
      predicate_param_of_name pre_vars_name;
      predicate_param_of_name post_vars_name;
    ]
    @ List.filter_map param_of_binder post_input_binders
  in
  let post_pred_decl =
    Ptree.Dlogic
      [
        {
          ld_loc = loc;
          ld_ident = ident post_pred_name;
          ld_params = post_pred_params;
          ld_type = None;
          ld_def = Some grouped.post_body;
        };
      ]
  in
  let post_call pre_snapshot_name =
    let pre_vars_term = mk_term (Tident (qid1 pre_snapshot_name)) in
    let vars_term = mk_term (Tident (qid1 ctx.env.rec_name)) in
    let args =
      [ pre_vars_term; vars_term ]
      @ List.filter_map binder_term post_input_binders
    in
    mk_term (Tidapp (qid1 post_pred_name, args))
  in
  let spc =
    {
      Ptree.sp_pre = [ grouped.pre_term ];
      sp_post = [];
      sp_xpost = [];
      sp_reads = [];
      sp_writes = [];
      sp_alias = [];
      sp_variant = [];
      sp_checkrw = false;
      sp_diverge = false;
      sp_partial = false;
    }
  in
  let pre_snapshot_name = "__pre_snapshot" in
  let snapshot_expr =
    ctx.env.rec_vars
    |> List.map (fun field_name -> (qid1 field_name, field ctx.env field_name))
    |> fun fields -> mk_expr (Erecord fields)
  in
  let helper_body =
    let proof_assert =
      mk_expr (Eassert (Expr.Assert, post_call pre_snapshot_name))
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
    helper_binders_without_unused_parameters ctx.inputs spc helper_body
  in
  let fn = helper_function helper_inputs spc helper_body in
  {
    helper_name = helper_name.Ptree.id_str;
    decls =
      local_shared_decls
      @ [ post_pred_decl; Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ];
    pre_labels = [ "Grouped product preconditions" ];
    post_labels = [];
  }

let record_singleton_split_chunk ctx ~split_due_to_cost (i, sc, t) =
  let entries = [ (i, sc, t) ] in
  let grouped =
    Product_groups.grouped_kernel_terms ~env:ctx.env ~pre_vars_name
      ~post_vars_name ~step_pre_terms_with_rec:ctx.step_pre_terms_with_rec
      ~step_post_terms_with_rec:ctx.step_post_terms_with_rec entries
  in
  record_group_metrics ctx
    ~group_name:(Step_names.product_step_helper_name ~index:i sc.step)
    ~emitted_as_group:false ~split_due_to_cost ~entries
    ~distinct_pre_count:grouped.distinct_pre_count
    ~distinct_post_count:grouped.distinct_post_count
    ~post_implication_count:grouped.post_implication_count
    ~pre_text_bytes:grouped.pre_text_bytes
    ~post_text_bytes:grouped.post_text_bytes
    ~estimated_cost:grouped.estimated_cost

let kernel_step_helper_units ctx step_contracts =
  Product_groups.group_kernel_helpers ~env:ctx.env ~pre_vars_name
    ~post_vars_name ~group_why3_product_steps:ctx.group_why3_product_steps
    ~max_cost:ctx.why3_product_step_group_max_cost
    ~simplify_runtime_actions:ctx.simplify_why3_runtime_actions
    ~step_pre_terms_with_rec:ctx.step_pre_terms_with_rec
    ~step_post_terms_with_rec:ctx.step_post_terms_with_rec
    ~build_individual:(build_individual_kernel_helper ctx)
    ~build_grouped:(build_grouped_kernel_helper ctx)
    ~record_singleton_split_chunk:(record_singleton_split_chunk ctx)
    step_contracts
