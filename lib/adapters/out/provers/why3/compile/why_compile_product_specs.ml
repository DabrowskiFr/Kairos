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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *---------------------------------------------------------------------------*)

(** Direct WhyML contracts for individual and grouped product steps. *)

open Why3
open Ptree
open Why_compile_expr
open Why_compile_ptree_helpers

module Obligations =
  Kairos_verification_obligations.Verification_obligations

module Proof_ir =
  Kairos_verification_obligations.Verification_proof_ir

let formula_term_with_rec formula_sharing env rec_name formula =
  Why_compile_formula_sharing.compile formula_sharing
    ~env:{ env with rec_name } formula

let state_guard env rec_name state_name =
  let local_env = { env with rec_name } in
  term_eq (term_of_var local_env "st") (mk_term (Tident (qid1 state_name)))

let compile_condition formula_sharing env = function
  | Obligations.State_is state ->
      state_guard env env.rec_name state
  | Obligations.Formula formula ->
      formula_term_with_rec formula_sharing env env.rec_name formula
  | Obligations.Not_formula formula ->
      mk_term
        (Tnot
           (formula_term_with_rec formula_sharing env env.rec_name
              formula))

let compile_conditions formula_sharing env conditions =
  List.map (compile_condition formula_sharing env) conditions

type individual_contract = {
  decls : Ptree.decl list;
  spec : Ptree.spec;
  used_inputs : used_inputs;
}

type grouped_contract = {
  decls : Ptree.decl list;
  spec : Ptree.spec;
  post_call : pre_snapshot_name:string -> Ptree.term;
  used_inputs : used_inputs;
}

let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ])

let individual_helper_contract ~env ~inputs ~formula_sharing ~formula_imports
    ~helper_name ~bundles (individual : Proof_ir.individual) =
  let pre_formulas =
    Obligations.formulas_of_conditions individual.preconditions
  in
  let pre_terms, pre_used =
    collect_used_inputs env (fun env ->
        compile_conditions formula_sharing env
          individual.preconditions)
  in
  let pre_decl, pre_call =
    Why_compile_bundles.predicate_decl_and_call ~inputs ~used_inputs:pre_used
      ~name:(helper_name ^ "_pre") pre_terms
  in
  let post_decls, post_terms, post_used, local_post_formulas =
    match individual.shared_postcondition_id with
    | Some shared_postcondition_id ->
        let import_, call, used_inputs =
          Why_compile_bundles.shared_postcondition_call bundles
            shared_postcondition_id
        in
        ([ import_ ], [ call ], used_inputs, [])
    | None ->
        let terms, used_inputs =
          collect_used_inputs env (fun env ->
              compile_conditions formula_sharing env
                individual.postconditions)
        in
        ( [],
          terms,
          used_inputs,
          Obligations.formulas_of_conditions
            individual.postconditions )
  in
  {
    decls =
      formula_imports (pre_formulas @ local_post_formulas)
      @ post_decls @ [ pre_decl ];
    spec =
      {
        Ptree.sp_pre = [ pre_call ];
        sp_post = List.rev_map mk_post post_terms;
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      };
    used_inputs = StringSet.union pre_used post_used;
  }

let predicate_param_of_name name =
  (loc, Some (ident name), false, Ptree.PTtyapp (qid1 "vars", []))

let pre_vars_name = "__pre_vars"
let post_vars_name = "__post_vars"

let conjunction_term formula_sharing env conditions =
  compile_conditions formula_sharing env conditions
  |> term_and_list

let alternatives_term formula_sharing env alternatives =
  alternatives
  |> List.map (conjunction_term formula_sharing env)
  |> term_or_list

let grouped_post_body formula_sharing env
    (grouped : Proof_ir.grouped) =
  let pre_env = { env with rec_name = pre_vars_name } in
  let post_env = { env with rec_name = post_vars_name } in
  let implications =
    grouped.conditional_posts
    |> List.map (fun (post : Proof_ir.conditional_post) ->
           term_implies
             (alternatives_term formula_sharing pre_env
                post.alternatives)
             (conjunction_term formula_sharing post_env
                post.conclusions))
    |> term_and_list
  in
  match grouped.common_preconditions with
  | [] -> implications
  | common ->
      term_implies
        (conjunction_term formula_sharing pre_env common)
        implications

let grouped_formulas (grouped : Proof_ir.grouped) =
  let conditional_formulas =
    grouped.conditional_posts
    |> List.concat_map (fun (post : Proof_ir.conditional_post) ->
           List.concat_map Obligations.formulas_of_conditions
             post.alternatives
           @ Obligations.formulas_of_conditions post.conclusions)
  in
  List.concat_map Obligations.formulas_of_conditions
    grouped.precondition_alternatives
  @ Obligations.formulas_of_conditions grouped.common_preconditions
  @ conditional_formulas

let grouped_helper_contract ~env ~inputs ~formula_sharing
    ~formula_imports ~post_pred_name (grouped : Proof_ir.grouped) =
  let pre_term, pre_inputs =
    collect_used_inputs env (fun env ->
        alternatives_term formula_sharing env
          grouped.precondition_alternatives)
  in
  let post_body, post_inputs =
    collect_used_inputs env (fun env ->
        grouped_post_body formula_sharing env grouped)
  in
  let input_binders_without_vars =
    match inputs with _vars :: rest -> rest | [] -> []
  in
  let post_input_binders =
    List.filter
      (fun (_, id_opt, _, _) ->
        match id_opt with
        | None -> true
        | Some id -> StringSet.mem id.Ptree.id_str post_inputs)
      input_binders_without_vars
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
          ld_def = Some post_body;
        };
      ]
  in
  let post_call ~pre_snapshot_name =
    let args =
      [
        mk_term (Tident (qid1 pre_snapshot_name));
        mk_term (Tident (qid1 env.rec_name));
      ]
      @ List.filter_map binder_term post_input_binders
    in
    mk_term (Tidapp (qid1 post_pred_name, args))
  in
  let spec =
    {
      Ptree.sp_pre = [ pre_term ];
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
  {
    decls =
      formula_imports (grouped_formulas grouped)
      @ [ post_pred_decl ];
    spec;
    post_call;
    used_inputs = StringSet.union pre_inputs post_inputs;
  }
