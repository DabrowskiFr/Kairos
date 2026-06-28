(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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

[@@@ocaml.warning "-8"]

open Why3
open Ptree
open Pretty
open Core_syntax
open Pre_k_layout
open Why_compile_expr

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let rec hexpr_size (h : Core_syntax.hexpr) : int =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> 1
  | HUn (_, inner) -> 1 + hexpr_size inner
  | HPred (_, hs) | HFunCall (_, hs) ->
      1 + List.fold_left (fun acc h -> acc + hexpr_size h) 0 hs
  | HBin (_, a, b) | HCmp (_, a, b) -> 1 + hexpr_size a + hexpr_size b

type step_contract_info = {
  step : Why_runtime_view.runtime_product_transition_view;
  pre : Why3.Ptree.term list;
  pre_labels : string list;
  post : Why3.Ptree.term list;
  post_labels : string list;
  local_cuts : Why3.Ptree.term list;
  forbidden : Why3.Ptree.term list;
  forbidden_labels : string list;
}

type contract_info = { step_contracts : step_contract_info list }

let build_contracts
    ~(abstract_formula : in_post:bool -> hexpr -> Ptree.term option)
    ~(local_cut_candidate : hexpr -> bool) ~(env : Why_compile_expr.env)
    ~(runtime : Why_runtime_view.t) ~(simplify_formulas : bool)
    ~(deduplicate_terms : bool) : contract_info =
  let normalize_fo f = if simplify_formulas then simplify_fo f else f in
  let maybe_uniq_labeled terms =
    if not deduplicate_terms then terms
    else
      let rec loop seen acc = function
        | [] -> List.rev acc
        | (term, label) :: rest ->
            let key = string_of_term term in
            if List.mem key seen then loop seen acc rest
            else loop (key :: seen) ((term, label) :: acc) rest
      in
      loop [] [] terms
  in
  let split_labeled terms = (List.map fst terms, List.map snd terms) in
  let family_label ~default (formula : Ir.summary_formula) =
    match formula.meta.family with
    | Some "propagation_requires" -> "Propagation requirements"
    | Some "state_invariant_requires" -> "State invariants"
    | Some "stability_requires" -> "Stability requirements"
    | Some "common_destination_invariant_ensures" -> "Destination invariants"
    | Some family -> family
    | None -> default
  in
  let compile_formula_term ~in_post logic =
    match abstract_formula ~in_post logic with
    | Some term -> term
    | None ->
        let normalized = normalize_fo logic in
        begin match abstract_formula ~in_post normalized with
        | Some term -> term
        | None ->
            Why_compile_expr.compile_local_fo_formula_term ~in_post env
              normalized
        end
  in
  let compile_unshared_formula_term ~in_post logic =
    let normalized = normalize_fo logic in
    Why_compile_expr.compile_local_fo_formula_term ~in_post env normalized
  in
  let compile_labeled_formula ~in_post ~default_label (f : Ir.summary_formula) :
      (Ptree.term * string) list =
    [
      ( compile_formula_term ~in_post f.logic,
        family_label ~default:default_label f );
    ]
  in
  let rec split_top_level_and (f : Core_syntax.hexpr) : Core_syntax.hexpr list =
    match f.hexpr with
    | HBin (And, a, b) -> split_top_level_and a @ split_top_level_and b
    | _ -> [ f ]
  in
  let local_cut_formulas (formulas : Ir.summary_formula list) :
      Core_syntax.hexpr list =
    formulas
    |> List.concat_map (fun (formula : Ir.summary_formula) ->
        let pieces = split_top_level_and formula.logic in
        let selected_pieces = List.filter local_cut_candidate pieces in
        match selected_pieces with
        | [] when local_cut_candidate formula.logic -> [ formula.logic ]
        | [] -> []
        | facts -> facts)
    |> List.sort_uniq Stdlib.compare
    |> List.sort (fun a b ->
        match Int.compare (hexpr_size b) (hexpr_size a) with
        | 0 -> Stdlib.compare a b
        | c -> c)
  in
  let compile_forbidden_formula (f : Ir.summary_formula) : Ptree.term * string =
    (* Negated shared predicates are compact for Why3 but substantially harder
       for SMT on exclusion VCs; keep forbidden facts transparent. *)
    let term = compile_unshared_formula_term ~in_post:true f.logic in
    (mk_term (Tnot term), family_label ~default:"Excluded unsafe cases" f)
  in
  let compile_step_contract
      (pc : Why_runtime_view.runtime_product_transition_view) :
      step_contract_info =
    let forbidden_labeled =
      pc.forbidden |> List.map compile_forbidden_formula |> maybe_uniq_labeled
    in
    let pre_labeled =
      (pc.requires
      |> List.concat_map
           (compile_labeled_formula ~in_post:false
              ~default_label:"Transition requires"))
      @ (pc.local_requires
        |> List.concat_map
             (compile_labeled_formula ~in_post:false
                ~default_label:"Product reachability"))
      |> maybe_uniq_labeled
    in
    let post_labeled =
      ((pc.ensures
       |> List.concat_map
            (compile_labeled_formula ~in_post:true
               ~default_label:"Transition ensures"))
      @ (pc.elaboration_checks
         |> List.concat_map
              (compile_labeled_formula ~in_post:true
                 ~default_label:"Elaboration checks")))
      |> maybe_uniq_labeled
    in
    let pre, pre_labels = split_labeled pre_labeled in
    let post, post_labels = split_labeled post_labeled in
    let forbidden, forbidden_labels = split_labeled forbidden_labeled in
    let local_cuts =
      (pc.ensures @ pc.elaboration_checks)
      |> local_cut_formulas
      |> List.map (fun logic ->
          ( compile_unshared_formula_term ~in_post:true logic,
            "Local cut assertions" ))
      |> maybe_uniq_labeled |> List.map fst
    in
    {
      step = pc;
      pre;
      pre_labels;
      post;
      post_labels;
      forbidden;
      forbidden_labels;
      local_cuts;
    }
  in
  let compiled_step_contracts =
    List.map compile_step_contract runtime.product_transitions
  in
  { step_contracts = compiled_step_contracts }
