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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Core_syntax

type step_class = Canonical_obligations.step_class =
  | StepSafe
  | StepBadGuarantee

type covered_case = Canonical_obligations.covered_case =
  | CoveredSafeCase of Ir.safe_product_case
  | CoveredUnsafeCase of Ir.unsafe_product_case

type step_contract = {
  transition_id : string;
  program_transition_id : int;
  program_step : Ir.transition;
  step_class : step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  assume_guard : Ir.summary_formula;
  requires : Ir.summary_formula list;
  runtime_requires : Ir.summary_formula list;
  propagates : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
  elaboration_checks : Ir.summary_formula list;
  forbidden : Ir.summary_formula list;
  summary_identity : Product_summary_projection.summary_identity;
  covered_cases : covered_case list;
}

type t = {
  canonical : Canonical_obligations.stage2;
  product_summaries : Product_summary_projection.t;
  step_contracts : step_contract list;
}

let rec split_top_level_or (f : Core_syntax.hexpr) : Core_syntax.hexpr list =
  match f.hexpr with
  | HBin (Or, a, b) -> split_top_level_or a @ split_top_level_or b
  | _ -> [ f ]

let transition_requires_without_assume_guard
    (summary : Product_summary_projection.summary) =
  summary.requires
  |> List.filter (fun (f : Ir.summary_formula) ->
         f.logic <> summary.identity.assume_guard)

let common_requires (summary : Product_summary_projection.summary) =
  summary.propagation_requires @ transition_requires_without_assume_guard summary

let safe_contract ~(assume_guard : Ir.summary_formula) ~requires
    (summary : Product_summary_projection.summary) =
  match summary.safe_cases with
  | [] -> None
  | first_case :: _ ->
      Some
        {
          transition_id =
            Printf.sprintf "tr_%d" summary.identity.program_transition_id;
          program_transition_id = summary.identity.program_transition_id;
          program_step = summary.identity.program_step;
          step_class = StepSafe;
          product_src = summary.identity.product_src;
          product_dst = first_case.product_dst;
          assume_guard;
          requires;
          runtime_requires = summary.runtime_requires;
          propagates =
            List.map
              (fun (case : Ir.safe_product_case) -> case.admissible_guard)
              summary.safe_cases;
          ensures = summary.ensures;
          elaboration_checks = summary.elaboration_checks;
          forbidden = [];
          summary_identity = summary.identity;
          covered_cases =
            List.map (fun case -> CoveredSafeCase case) summary.safe_cases;
        }

let bad_guarantee_contract ~(assume_guard : Ir.summary_formula) ~requires
    (summary : Product_summary_projection.summary) =
  match summary.unsafe_cases with
  | [] -> None
  | first_case :: _ ->
      let forbidden =
        summary.unsafe_cases
        |> List.concat_map (fun (case : Ir.unsafe_product_case) ->
               case.excluded_guard.logic |> split_top_level_or
               |> List.map Ir_formula.make)
      in
      Some
        {
          transition_id =
            Printf.sprintf "tr_%d" summary.identity.program_transition_id;
          program_transition_id = summary.identity.program_transition_id;
          program_step = summary.identity.program_step;
          step_class = StepBadGuarantee;
          product_src = summary.identity.product_src;
          product_dst = first_case.product_dst;
          assume_guard;
          requires;
          runtime_requires = summary.runtime_requires;
          propagates = [];
          ensures = [];
          elaboration_checks = [];
          forbidden;
          summary_identity = summary.identity;
          covered_cases =
            List.map (fun case -> CoveredUnsafeCase case) summary.unsafe_cases;
        }

let contracts_of_summary (summary : Product_summary_projection.summary) :
    step_contract list =
  let assume_guard = Ir_formula.make summary.identity.assume_guard in
  let requires = common_requires summary in
  [
    safe_contract ~assume_guard ~requires summary;
    bad_guarantee_contract ~assume_guard ~requires summary;
  ]
  |> List.filter_map Fun.id

let of_product_summaries (product_summaries : Product_summary_projection.t) :
    t =
  let step_contracts =
    List.concat_map contracts_of_summary product_summaries.summaries
  in
  let canonical = Canonical_obligations.build_stage2 product_summaries in
  {
    canonical;
    product_summaries;
    step_contracts;
  }

let of_ir_node (node : Ir.node_ir) : t =
  let reachability = Product_reachability.build ~node in
  let runtime_requires_of_summary (summary : Ir.product_step_summary) =
    Product_reachability.local_requires_of_product_state reachability
      summary.identity.product_src
    |> List.map Ir_formula.make
  in
  Product_summary_projection.of_ir_node ~runtime_requires_of_summary node
  |> of_product_summaries
