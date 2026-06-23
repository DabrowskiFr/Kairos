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
module Labels = Why_compile_product_spec_labels
module Spec_terms = Why_compile_product_spec_terms
module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  env : Why_compile_expr.env;
  pre_family_terms_by_step : Ptree.term list list;
  post_family_terms_by_step : Ptree.term list list;
  pre_family_bundle_counts : (string, int) Hashtbl.t;
  post_family_bundle_counts : (string, int) Hashtbl.t;
  predicate_bundle_decl_and_call :
    name:string -> Ptree.term list -> Ptree.decl * Ptree.term;
  shared_pre_bundle_call : Ptree.term list -> Ptree.decl * Ptree.term * StringSet.t;
  shared_post_bundle_call : Ptree.term list -> Ptree.decl * Ptree.term * StringSet.t;
}

type individual_contract = {
  pre_imports : Ptree.decl list;
  post_decls : Ptree.decl list;
  spec : Ptree.spec;
  direct_shared_terms : Ptree.term list;
  imported_shared_names : StringSet.t;
  pre_labels : string list;
  post_labels : string list;
}

type grouped_contract = {
  post_pred_decl : Ptree.decl;
  spec : Ptree.spec;
  shared_terms : Ptree.term list;
  post_call : pre_snapshot_name:string -> Ptree.term;
  pre_labels : string list;
  post_labels : string list;
}

let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ])

let predicate_param_of_name name =
  (loc, Some (ident name), false, Ptree.PTtyapp (qid1 "vars", []))

let term_context ctx : Spec_terms.context =
  {
    env = ctx.env;
    pre_family_terms_by_step = ctx.pre_family_terms_by_step;
    post_family_terms_by_step = ctx.post_family_terms_by_step;
    pre_family_bundle_counts = ctx.pre_family_bundle_counts;
    post_family_bundle_counts = ctx.post_family_bundle_counts;
    predicate_bundle_decl_and_call = ctx.predicate_bundle_decl_and_call;
    shared_pre_bundle_call = ctx.shared_pre_bundle_call;
    shared_post_bundle_call = ctx.shared_post_bundle_call;
  }

let individual_helper_contract ctx ~step_index ~helper_name
    (sc : Why_contracts.step_contract_info) =
  let terms =
    Spec_terms.individual (term_context ctx) ~step_index ~helper_name sc
  in
  let spec =
    {
      Ptree.sp_pre = [ terms.pre_term ];
      sp_post = List.rev_map mk_post terms.post_terms;
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
    pre_imports = terms.pre_decls;
    post_decls = terms.post_decls;
    spec;
    direct_shared_terms =
      terms.raw_pre_terms
      @ (if terms.bundle_post_terms then [] else terms.raw_post_terms)
      @ sc.local_cuts;
    imported_shared_names = terms.imported_shared_names;
    pre_labels = [ Labels.product_step_preconditions ];
    post_labels = terms.post_labels;
  }

let grouped_helper_contract ~env ~inputs ~pre_vars_name ~post_vars_name
    ~post_pred_name (grouped : Why_compile_product_groups.grouped_terms) =
  let post_used_names = names_of_term grouped.post_body StringSet.empty in
  let input_binders_without_vars =
    match inputs with _vars :: rest -> rest | [] -> []
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
  let post_call ~pre_snapshot_name =
    let pre_vars_term = mk_term (Tident (qid1 pre_snapshot_name)) in
    let vars_term = mk_term (Tident (qid1 env.rec_name)) in
    let args =
      [ pre_vars_term; vars_term ]
      @ List.filter_map binder_term post_input_binders
    in
    mk_term (Tidapp (qid1 post_pred_name, args))
  in
  let spec =
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
  {
    post_pred_decl;
    spec;
    shared_terms = [ grouped.pre_term; grouped.post_body ];
    post_call;
    pre_labels = [ Labels.grouped_product_preconditions ];
    post_labels = [];
  }
