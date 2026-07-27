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

let simplify_fo (f : Core_syntax.historical Core_syntax.hexpr) : Core_syntax.historical Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let disj_fo (fs : Core_syntax.historical Core_syntax.hexpr list) : Core_syntax.historical Core_syntax.hexpr option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left Core_syntax_builders.mk_hor f rest |> simplify_fo)

let input_names (n : Core_syntax.historical Abs.node_ir) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Core_syntax.historical Abs.node_ir) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let invariants_of_state (n : Core_syntax.historical Abs.node_ir) : ident -> Core_syntax.historical Core_syntax.hexpr list =
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

let add_unique_formula_with_status ~family (f : Core_syntax.historical Core_syntax.hexpr)
    (xs : Core_syntax.historical Abs.summary_formula list) : Core_syntax.historical Abs.summary_formula list * bool =
  if List.exists (fun (x : Core_syntax.historical Abs.summary_formula) -> x.logic = f) xs then (xs, false)
  else (xs @ [ Ir_formula.make ~family f ], true)

let add_formula_family ~record_family ~family_name formulas acc =
  let inserted, acc =
    List.fold_left
      (fun (inserted, acc) f ->
        let acc, was_inserted =
          add_unique_formula_with_status ~family:family_name f acc
        in
        let inserted = if was_inserted then f :: inserted else inserted in
        (inserted, acc))
      ([], acc) formulas
  in
  record_family ~family_name ~candidates:formulas ~inserted:(List.rev inserted);
  acc

let formula_mem (f : Core_syntax.historical Core_syntax.hexpr) (xs : Core_syntax.historical Core_syntax.hexpr list) : bool =
  List.exists (( = ) f) xs

let enrich_product_step_summary ~(record_family : family_name:string ->
    candidates:Core_syntax.historical Core_syntax.hexpr list -> inserted:Core_syntax.historical Core_syntax.hexpr list -> unit)
    ~(node : Core_syntax.historical Abs.node_ir)
    ~(product_characteristics : Product_characteristics.t)
    (pc : Core_syntax.historical Abs.product_step_summary) :
    Core_syntax.historical Abs.product_step_summary =
  let is_input = is_input_of_node node in
  let invs_of_state = invariants_of_state node in
  let safe_disjunction =
    pc.safe_cases
    |> List.map (fun (case : Core_syntax.historical Abs.safe_product_case) -> case.admissible_guard.logic)
    |> disj_fo
  in
  let destination_invariants_by_case =
    pc.safe_cases
    |> List.map (fun (case : Core_syntax.historical Abs.safe_product_case) ->
           (case, invs_of_state case.product_dst.prog_state))
  in
  let common_destination_invariants =
    match destination_invariants_by_case with
    | [] -> []
    | (_, invs) :: rest ->
        invs
        |> List.filter (fun inv ->
               List.for_all
                 (fun (_, other_invs) -> formula_mem inv other_invs)
                 rest)
  in
  let shifted_common_destination_invariants =
    common_destination_invariants
    |> List.map (shift_formula_backward_inputs ~is_input)
    |> List.map simplify_fo
  in
  let shifted_guarded_destination_invariants =
    destination_invariants_by_case
    |> List.concat_map (fun ((case : Core_syntax.historical Abs.safe_product_case), invs) ->
           invs
           |> List.filter (fun inv ->
                  not (formula_mem inv common_destination_invariants))
           |> List.map (fun inv ->
                  let shifted = shift_formula_backward_inputs ~is_input inv in
                  Core_syntax_builders.mk_himp case.admissible_guard.logic
                    shifted
                  |> simplify_fo))
    |> List.sort_uniq compare
  in
  let shifted_product_characteristics =
    Product_characteristics.preservation_ensures product_characteristics
      ~node pc
  in
  let ensures =
    (pc.ensures
    |> add_formula_family ~record_family
         ~family_name:"safe_disjunction_ensures"
         (match safe_disjunction with None -> [] | Some f -> [ f ])
    |> add_formula_family ~record_family
         ~family_name:"common_destination_invariant_ensures"
         shifted_common_destination_invariants
    |> add_formula_family ~record_family
         ~family_name:"guarded_destination_invariant_ensures"
         shifted_guarded_destination_invariants
    |> add_formula_family ~record_family
         ~family_name:"product_characteristics_ensures"
         shifted_product_characteristics)
  in
  { pc with ensures }

type node_generation = { summaries : Core_syntax.historical Abs.product_step_summary list }

let compute_generation ~record_family ~(node : Core_syntax.historical Abs.node_ir) : node_generation =
  let product_characteristics = Product_characteristics.build ~node in
  {
    summaries =
      List.map
        (enrich_product_step_summary ~record_family ~node ~product_characteristics)
        node.summaries;
  }

let run_node ~record_family (n : Core_syntax.historical Abs.node_ir) : Core_syntax.historical Abs.node_ir =
  let post_generation = compute_generation ~record_family ~node:n in
  { n with summaries = post_generation.summaries }

let run_program ?observe_family (p : Core_syntax.historical Abs.node_ir list) : Core_syntax.historical Abs.node_ir list =
  let collector =
    match observe_family with
    | None -> None
    | Some _ -> Some (Ir_fact_family_metrics.create ())
  in
  let record_family ~family_name ~candidates ~inserted =
    match collector with
    | None -> ()
    | Some collector ->
        Ir_fact_family_metrics.add collector ~pass_name:"post" ~family_name
          ~candidates ~inserted
  in
  let result = List.map (run_node ~record_family) p in
  (match (collector, observe_family) with
  | Some collector, Some observer -> Ir_fact_family_metrics.emit collector observer
  | _ -> ());
  result
