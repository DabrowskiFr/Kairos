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

type step_class =
  | StepSafe
  | StepBadGuarantee

type step_contract = {
  transition_id : string;
  program_step : Ir.transition;
  step_class : step_class;
  product_src : Ir.product_state;
  assume_guard : Core_syntax.history_free Ir.summary_formula;
  requires : Core_syntax.history_free Ir.summary_formula list;
  runtime_requires : Core_syntax.history_free Ir.summary_formula list;
  ensures : Core_syntax.history_free Ir.summary_formula list;
  elaboration_checks : Core_syntax.history_free Ir.summary_formula list;
  forbidden : Core_syntax.history_free Ir.summary_formula list;
}

let preconditions (contract : step_contract) =
  contract.requires @ [ contract.assume_guard ] @ contract.runtime_requires

let postconditions (contract : step_contract) =
  contract.ensures @ contract.elaboration_checks

let exclusions (contract : step_contract) = contract.forbidden

let rec split_top_level_or
    (f : Core_syntax.history_free Core_syntax.hexpr) :
    Core_syntax.history_free Core_syntax.hexpr list =
  match f.hexpr with
  | HBin (Or, a, b) -> split_top_level_or a @ split_top_level_or b
  | _ -> [ f ]

let common_requires
    (summary : Core_syntax.history_free Ir.product_step_summary) =
  summary.propagation_requires @ summary.requires

let transition_id_of_summary
    (summary : Core_syntax.history_free Ir.product_step_summary) =
  Printf.sprintf "tr_%d" summary.trace.step_uid

let safe_contract ~(assume_guard : Core_syntax.history_free Ir.summary_formula)
    ~requires ~runtime_requires
    (summary : Core_syntax.history_free Ir.product_step_summary) =
  match summary.safe_cases with
  | [] -> None
  | _ ->
      Some
        {
          transition_id = transition_id_of_summary summary;
          program_step = summary.identity.program_step;
          step_class = StepSafe;
          product_src = summary.identity.product_src;
          assume_guard;
          requires;
          runtime_requires;
          ensures = summary.ensures;
          elaboration_checks = summary.elaboration_checks;
          forbidden = [];
        }

let bad_guarantee_contract
    ~(assume_guard : Core_syntax.history_free Ir.summary_formula) ~requires
    ~runtime_requires
    (summary : Core_syntax.history_free Ir.product_step_summary) =
  match summary.unsafe_cases with
  | [] -> None
  | _ ->
      let forbidden =
        summary.unsafe_cases
        |> List.concat_map
             (fun
               (case : Core_syntax.history_free Ir.unsafe_product_case)
             ->
               case.excluded_guard.logic |> split_top_level_or
               |> List.map Ir_formula.make)
      in
      Some
        {
          transition_id = transition_id_of_summary summary;
          program_step = summary.identity.program_step;
          step_class = StepBadGuarantee;
          product_src = summary.identity.product_src;
          assume_guard;
          requires;
          runtime_requires;
          ensures = [];
          elaboration_checks = [];
          forbidden;
        }

let contracts_of_summary
    ~runtime_requires
    (summary : Core_syntax.history_free Ir.product_step_summary) :
    step_contract list =
  let assume_guard = Ir_formula.make summary.identity.assume_guard in
  let requires = common_requires summary in
  [
    safe_contract ~assume_guard ~requires ~runtime_requires summary;
    bad_guarantee_contract ~assume_guard ~requires ~runtime_requires summary;
  ]
  |> List.filter_map Fun.id

let of_ir_node (node : Core_syntax.history_free Ir.node_ir) :
    step_contract list =
  let reachability = Product_reachability.build_history_free ~node in
  node.summaries
  |> List.concat_map
       (fun
         (summary : Core_syntax.history_free Ir.product_step_summary)
       ->
         let runtime_requires =
           Product_reachability.local_requires_of_product_state reachability
             summary.identity.product_src
           |> List.map Ir_formula.make
         in
         contracts_of_summary ~runtime_requires summary)
