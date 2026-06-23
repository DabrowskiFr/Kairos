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
module Labels = Why_compile_product_spec_labels
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

type individual = {
  pre_decls : Ptree.decl list;
  post_decls : Ptree.decl list;
  pre_term : Ptree.term;
  post_terms : Ptree.term list;
  raw_pre_terms : Ptree.term list;
  raw_post_terms : Ptree.term list;
  bundle_post_terms : bool;
  imported_shared_names : StringSet.t;
  post_labels : string list;
}

let combine_labeled_terms ~terms ~labels =
  if List.length terms <> List.length labels then
    invalid_arg "Why_compile_product_spec_terms: contract terms/labels out of sync"
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

let product_state_guard env (sc : Why_contracts.step_contract_info) =
  term_eq (term_of_var env "st") (mk_term (Tident (qid1 sc.step.src_state)))

let individual ctx ~step_index ~helper_name
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
    @ Labels.repeated Labels.shared_postcondition_facts post_family_terms
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
  {
    pre_decls = pre_imports @ pre_decls;
    post_decls;
    pre_term;
    post_terms;
    raw_pre_terms;
    raw_post_terms;
    bundle_post_terms;
    imported_shared_names;
    post_labels =
      Labels.individual_post_labels ~bundle_post_terms ~raw_post_terms
        ~raw_post_labels;
  }
