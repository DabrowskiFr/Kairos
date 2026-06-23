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

let combine_labeled_terms ~terms ~labels =
  if List.length terms <> List.length labels then
    invalid_arg "Why_compile_product_specs: contract terms/labels out of sync"
  else List.combine terms labels

let remove_labeled_terms terms labels removed =
  let removed_keys =
    removed
    |> List.map string_of_term
    |> List.fold_left (fun acc key -> StringSet.add key acc) StringSet.empty
  in
  combine_labeled_terms ~terms ~labels
  |> List.filter (fun (term, _label) ->
         not (StringSet.mem (string_of_term term) removed_keys))
  |> List.split

let repeated_label label terms = List.map (fun _ -> label) terms

let product_state_guard env (sc : Why_contracts.step_contract_info) =
  term_eq (term_of_var env "st") (mk_term (Tident (qid1 sc.step.src_state)))

let individual_helper_contract ctx ~step_index ~helper_name
    (sc : Why_contracts.step_contract_info) =
  let state_guard = product_state_guard ctx.env sc in
  let pre_family_terms =
    Option.value ~default:[] (List.nth_opt ctx.pre_family_terms_by_step step_index)
  in
  let share_pre_family_bundle =
    Bundles.should_share_bundle ctx.pre_family_bundle_counts pre_family_terms
  in
  let pre_terms =
    if share_pre_family_bundle then Bundles.remove_terms pre_family_terms sc.pre
    else sc.pre
  in
  let pre_imports, pre_family_terms =
    if share_pre_family_bundle then
      let import_, call, _shared_names =
        ctx.shared_pre_bundle_call pre_family_terms
      in
      ([ import_ ], [ call ])
    else ([], [])
  in
  let post_family_terms =
    Option.value ~default:[]
      (List.nth_opt ctx.post_family_terms_by_step step_index)
  in
  let share_post_family_bundle =
    Bundles.should_share_bundle ctx.post_family_bundle_counts post_family_terms
    && not (List.exists term_has_old post_family_terms)
  in
  let post_terms, post_labels =
    if share_post_family_bundle then
      remove_labeled_terms sc.post sc.post_labels post_family_terms
    else (sc.post, sc.post_labels)
  in
  let post_imports, post_family_terms, post_family_shared_names =
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
  let pre_decls, pre_term =
    let pre_decl, call =
      ctx.predicate_bundle_decl_and_call
        ~name:(helper_name ^ "_pre")
        raw_pre_terms
    in
    ([ pre_decl ], call)
  in
  let post_decls, post_terms, imported_shared_names =
    if not bundle_post_terms then
      (post_imports, raw_post_terms, post_family_shared_names)
    else
      let post_import, call, shared_names =
        ctx.shared_post_bundle_call raw_post_terms
      in
      ( post_imports @ [ post_import ],
        [ call ],
        StringSet.union post_family_shared_names shared_names )
  in
  let spec =
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
  {
    pre_imports = pre_imports @ pre_decls;
    post_decls;
    spec;
    direct_shared_terms =
      raw_pre_terms
      @ (if bundle_post_terms then [] else raw_post_terms)
      @ sc.local_cuts;
    imported_shared_names;
    pre_labels = [ "Product step preconditions" ];
    post_labels =
      (if bundle_post_terms && raw_post_terms <> [] then
         [ "Product step postconditions" ]
       else raw_post_labels);
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
    pre_labels = [ "Grouped product preconditions" ];
    post_labels = [];
  }
