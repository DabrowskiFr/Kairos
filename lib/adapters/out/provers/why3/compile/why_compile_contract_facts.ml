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
open Core_syntax
open Why_compile_expr
open Why_compile_ptree_helpers

module Bundles = Why_compile_bundles

type context = {
  env : Why_compile_expr.env;
  simplify_why3_formulas : bool;
  abstract_formula : in_post:bool -> Core_syntax.hexpr -> Ptree.term option;
  abstract_formula_with_rec : string -> Core_syntax.hexpr -> Ptree.term option;
}

type product_helper_facts = {
  pre_family_terms_by_step : Ptree.term list list;
  post_family_terms_by_step : Ptree.term list list;
  pre_family_bundle_counts : (string, int) Hashtbl.t;
  post_family_bundle_counts : (string, int) Hashtbl.t;
  step_pre_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Ptree.term list;
  step_post_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Ptree.term list;
}

let contract_formula_term ctx ~in_post logic =
  match ctx.abstract_formula ~in_post logic with
  | Some term -> term
  | None ->
      let normalized =
        if ctx.simplify_why3_formulas then Core_fo_simplifier.simplify logic
        else logic
      in
      begin
        match ctx.abstract_formula ~in_post normalized with
        | Some term -> term
        | None -> compile_local_fo_formula_term ~in_post ctx.env normalized
      end

let formula_family_is families (formula : Ir.summary_formula) =
  match formula.meta.family with
  | None -> false
  | Some family -> List.mem family families

let sorted_unique_terms terms =
  terms
  |> List.sort_uniq (fun left right ->
         String.compare (string_of_term left) (string_of_term right))

let selected_family_terms ctx ~in_post families formulas =
  formulas
  |> List.filter (formula_family_is families)
  |> List.map (fun (formula : Ir.summary_formula) ->
         contract_formula_term ctx ~in_post formula.logic)
  |> sorted_unique_terms

let formula_term_with_rec ctx ?(allow_shared = true) ~in_post rec_name logic =
  let normalized =
    if ctx.simplify_why3_formulas then Core_fo_simplifier.simplify logic
    else logic
  in
  if allow_shared then
    match ctx.abstract_formula_with_rec rec_name logic with
    | Some term -> term
    | None -> begin
        match ctx.abstract_formula_with_rec rec_name normalized with
        | Some term -> term
        | None ->
            let local_env = { ctx.env with rec_name } in
            compile_local_fo_formula_term ~in_post local_env normalized
      end
  else
    let local_env = { ctx.env with rec_name } in
    compile_local_fo_formula_term ~in_post local_env normalized

let state_guard_with_rec ctx rec_name state_name =
  let local_env = { ctx.env with rec_name } in
  term_eq (term_of_var local_env "st") (mk_term (Tident (qid1 state_name)))

let step_pre_terms_with_rec ctx rec_name (sc : Why_contracts.step_contract_info) =
  state_guard_with_rec ctx rec_name sc.step.src_state
  :: ((sc.step.requires @ sc.step.local_requires)
     |> List.concat_map (fun (formula : Ir.summary_formula) ->
            [ formula_term_with_rec ctx ~in_post:false rec_name formula.logic ]))

let step_post_terms_with_rec ctx rec_name (sc : Why_contracts.step_contract_info) =
  let forbidden =
    sc.step.forbidden
    |> List.map (fun (formula : Ir.summary_formula) ->
           mk_term
             (Tnot
                (formula_term_with_rec ctx ~allow_shared:false ~in_post:true rec_name
                   formula.logic)))
  in
  let ensures =
    (sc.step.ensures @ sc.step.elaboration_checks)
    |> List.map (fun (formula : Ir.summary_formula) ->
           formula_term_with_rec ctx ~in_post:true rec_name formula.logic)
  in
  forbidden @ ensures

let product_helper_facts ctx ~(share_why3_facts : bool) step_contracts =
  let shared_pre_families =
    [ "state_invariant_requires"; "stability_requires" ]
  in
  let shared_post_families = [ "common_destination_invariant_ensures" ] in
  let pre_family_terms_by_step =
    if not share_why3_facts then List.map (fun _ -> []) step_contracts
    else
      step_contracts
      |> List.map (fun (sc : Why_contracts.step_contract_info) ->
             selected_family_terms ctx ~in_post:false shared_pre_families
               sc.step.requires)
  in
  let post_family_terms_by_step =
    if not share_why3_facts then List.map (fun _ -> []) step_contracts
    else
      step_contracts
      |> List.map (fun (sc : Why_contracts.step_contract_info) ->
             selected_family_terms ctx ~in_post:true shared_post_families
               sc.step.ensures)
  in
  {
    pre_family_terms_by_step;
    post_family_terms_by_step;
    pre_family_bundle_counts = Bundles.count_bundles pre_family_terms_by_step;
    post_family_bundle_counts = Bundles.count_bundles post_family_terms_by_step;
    step_pre_terms_with_rec = step_pre_terms_with_rec ctx;
    step_post_terms_with_rec = step_post_terms_with_rec ctx;
  }
