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

open Core_syntax
open Fo_time

module Abs = Ir

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr = f

let disj_fo (fs : Core_syntax.hexpr list) : Core_syntax.hexpr option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left Core_syntax_builders.mk_hor f rest |> simplify_fo)

let conj_fo (fs : Core_syntax.hexpr list) : Core_syntax.hexpr option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left Core_syntax_builders.mk_hand f rest)

let dedup_formulas (xs : Core_syntax.hexpr list) : Core_syntax.hexpr list = List.sort_uniq compare xs

let input_names (n : Abs.node_ir) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node_ir) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let same_product_state (a : Abs.product_state) (b : Abs.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let phase_invariant_of_product_state (n : Abs.node_ir) : Abs.product_state -> Core_syntax.hexpr option =
  let by_src = ref [] in
  let add state formulas =
    let rec loop acc = function
      | [] -> List.rev ((state, formulas) :: acc)
      | (state', prev) :: rest when same_product_state state state' ->
          List.rev_append acc ((state, dedup_formulas (formulas @ prev)) :: rest)
      | x :: rest -> loop (x :: acc) rest
    in
    by_src := loop [] !by_src
  in
  List.iter
    (fun (pc : Abs.product_step_summary) ->
      List.iter
        (fun (case : Abs.safe_product_case) ->
          add pc.identity.product_src [ case.admissible_guard.logic ])
        pc.safe_cases)
    n.summaries;
  fun st ->
    if st.guarantee_state_index = 0 then None
    else
      List.find_map
        (fun (state, fs) -> if same_product_state state st then Some fs else None)
        !by_src
      |> fun formulas -> Option.bind formulas disj_fo

let invariants_of_state (n : Abs.node_ir) : ident -> Core_syntax.hexpr list =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : Abs.state_invariant) ->
      if List.mem inv.state n.semantics.sem_states then (
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (inv.formula :: existing)))
    n.source_info.state_invariants;
  fun st ->
    (match Hashtbl.find_opt by_state st with
    | None -> []
    | Some xs -> List.sort_uniq compare xs)

let add_unique_formula (f : Core_syntax.hexpr)
    (xs : Abs.summary_formula list) : Abs.summary_formula list =
  if List.exists (fun (x : Abs.summary_formula) -> x.logic = f) xs then xs
  else xs @ [ Ir_formula.make f ]

let enrich_product_step_summary ~(node : Abs.node_ir) (pc : Abs.product_step_summary) :
    Abs.product_step_summary =
  let is_input = is_input_of_node node in
  let invs_of_state = invariants_of_state node in
  let phase_inv_of_product_state = phase_invariant_of_product_state node in
  let safe_disjunction =
    pc.safe_cases
    |> List.map (fun (case : Abs.safe_product_case) -> case.admissible_guard.logic)
    |> disj_fo
  in
  let shifted_destination_invariants =
    if pc.identity.product_src.assume_state_index = 0
       && pc.identity.product_src.guarantee_state_index = 0
    then
      pc.safe_cases
      |> List.concat_map (fun (case : Abs.safe_product_case) ->
             invs_of_state case.product_dst.prog_state
             |> List.map (shift_formula_backward_inputs ~is_input))
      |> List.sort_uniq compare
    else []
  in
  let destination_phase_invariants =
    pc.safe_cases
    |> List.filter_map (fun (case : Abs.safe_product_case) ->
           phase_inv_of_product_state case.product_dst
           |> Option.map (Core_syntax_builders.mk_himp case.admissible_guard.logic))
    |> List.sort_uniq compare
  in
  let ensures =
    (pc.ensures
    |> fun acc ->
    (match safe_disjunction with
    | None -> acc
    | Some f -> add_unique_formula f acc)
    |> fun acc ->
    List.fold_left
      (fun acc shifted_inv -> add_unique_formula shifted_inv acc)
      acc shifted_destination_invariants
    |> fun acc ->
    List.fold_left
      (fun acc phase_inv -> add_unique_formula phase_inv acc)
      acc destination_phase_invariants)
  in
  { pc with ensures }

type node_generation = { summaries : Abs.product_step_summary list }

let compute_generation ~(node : Abs.node_ir) : node_generation =
  { summaries = List.map (enrich_product_step_summary ~node) node.summaries }

let run_node (n : Abs.node_ir) : Abs.node_ir =
  let post_generation = compute_generation ~node:n in
  { n with summaries = post_generation.summaries }

let run_program (p : Abs.node_ir list) : Abs.node_ir list = List.map run_node p
