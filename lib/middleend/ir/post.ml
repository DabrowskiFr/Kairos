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

open Ast
open Fo_specs
open Fo_time
open Formula_origin
open Logic_pretty

module Abs = Ir

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let disj_fo (fs : Fo_formula.t list) : Fo_formula.t option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> Fo_formula.FOr (acc, x)) f rest |> simplify_fo)

let input_names (n : Abs.node_ir) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node_ir) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let rec iexpr_mentions_current_input ~(is_input : ident -> bool) (e : Ast.iexpr) =
  match e.iexpr with
  | IVar name -> is_input name
  | ILitInt _ | ILitBool _ -> false
  | IPar inner | IUn (_, inner) -> iexpr_mentions_current_input ~is_input inner
  | IBin (_, a, b) ->
      iexpr_mentions_current_input ~is_input a || iexpr_mentions_current_input ~is_input b

let hexpr_mentions_current_input ~(is_input : ident -> bool) = function
  | HNow e -> iexpr_mentions_current_input ~is_input e
  | HPreK _ -> false

let rec ltl_mentions_current_input ~(is_input : ident -> bool) (f : Ast.ltl) =
  match f with
  | LTrue | LFalse -> false
  | LAtom (FRel (a, _, b)) ->
      hexpr_mentions_current_input ~is_input a || hexpr_mentions_current_input ~is_input b
  | LAtom (FPred (_, hs)) -> List.exists (hexpr_mentions_current_input ~is_input) hs
  | LNot inner | LX inner | LG inner -> ltl_mentions_current_input ~is_input inner
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      ltl_mentions_current_input ~is_input a || ltl_mentions_current_input ~is_input b

let reject_current_input_invariant ~(node : Abs.node_ir) (inv : invariant_state_rel) : unit =
  let is_input = is_input_of_node node in
  if ltl_mentions_current_input ~is_input inv.formula then
    failwith
      (Printf.sprintf
         "State invariant for node %s in state %s mentions a current input (HNow on an input), \
          which is forbidden for node-entry invariants: %s"
         node.semantics.sem_nname inv.state (string_of_ltl inv.formula))

let invariant_of_state (n : Abs.node_ir) : ident -> Fo_formula.t option =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : invariant_state_rel) ->
      if List.mem inv.state n.semantics.sem_states then (
        reject_current_input_invariant ~node:n inv;
        let inv_fo = fo_formula_of_non_temporal_ltl_exn inv.formula in
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (inv_fo :: existing)))
    n.source_info.state_invariants;
  fun st ->
    (match Hashtbl.find_opt by_state st with
    | None -> None
    | Some xs -> conj_fo (List.sort_uniq compare xs))

  let add_unique_formula (origin : Formula_origin.t) (f : Fo_formula.t)
    (xs : Abs.summary_formula list) : Abs.summary_formula list =
  if List.exists (fun (x : Abs.summary_formula) -> x.logic = f) xs then xs
  else xs @ [ Ir_formula.with_origin origin f ]

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
    | Some f -> add_unique_formula Internal f acc)
    |> fun acc ->
    List.fold_left
      (fun acc shifted_inv -> add_unique_formula Invariant shifted_inv acc)
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
