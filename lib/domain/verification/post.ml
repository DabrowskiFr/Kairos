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

let input_names (n : Abs.node_ir) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node_ir) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let invariant_of_state (n : Abs.node_ir) : ident -> Core_syntax.hexpr option =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : Abs.state_invariant) ->
      if List.mem inv.state n.semantics.sem_states then (
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (inv.formula :: existing)))
    n.source_info.state_invariants;
  fun st ->
    (match Hashtbl.find_opt by_state st with
    | None -> None
    | Some xs -> conj_fo (List.sort_uniq compare xs))

let add_unique_formula (f : Core_syntax.hexpr)
    (xs : Abs.summary_formula list) : Abs.summary_formula list =
  if List.exists (fun (x : Abs.summary_formula) -> x.logic = f) xs then xs
  else xs @ [ Ir_formula.make f ]

let enrich_product_step_summary ~(node : Abs.node_ir) (pc : Abs.product_step_summary) :
    Abs.product_step_summary =
  let is_input = is_input_of_node node in
  let inv_of_state = invariant_of_state node in
  let safe_disjunction =
    pc.safe_cases
    |> List.map (fun (case : Abs.safe_product_case) -> case.admissible_guard.logic)
    |> disj_fo
  in
  let shifted_destination_invariants =
    pc.safe_cases
    |> List.filter_map (fun (case : Abs.safe_product_case) ->
           match inv_of_state case.product_dst.prog_state with
           | None -> None
           | Some inv -> Some (shift_formula_backward_inputs ~is_input inv))
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
      acc shifted_destination_invariants)
  in
  { pc with ensures }

type node_generation = { summaries : Abs.product_step_summary list }

let compute_generation ~(node : Abs.node_ir) : node_generation =
  { summaries = List.map (enrich_product_step_summary ~node) node.summaries }

let run_node (n : Abs.node_ir) : Abs.node_ir =
  let post_generation = compute_generation ~node:n in
  { n with summaries = post_generation.summaries }

let run_program (p : Abs.node_ir list) : Abs.node_ir list = List.map run_node p
