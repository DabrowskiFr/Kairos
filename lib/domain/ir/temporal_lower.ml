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

module Abs = Ir

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr = f

let required_temporal_layout (node : Abs.node_ir) : Abs.temporal_layout =
  let summary_formulas =
    let product_formulas =
      node.summaries
      |> List.concat_map (fun (summary : Abs.product_step_summary) ->
             Ir_formula.values (summary.propagation_requires @ summary.requires @ summary.ensures)
             @
             let case_formulas =
               List.concat_map
                 (fun (case : Abs.safe_product_case) -> [ case.admissible_guard ])
                 summary.safe_cases
               @ List.concat_map
                   (fun (case : Abs.unsafe_product_case) -> [ case.excluded_guard ])
                   summary.unsafe_cases
             in
             Ir_formula.values case_formulas)
    in
    product_formulas @ Ir_formula.values node.init_invariant_goals
  in
  Pre_k_layout.build_pre_k_infos_from_parts ~inputs:node.semantics.sem_inputs
    ~locals:node.semantics.sem_locals ~outputs:node.semantics.sem_outputs
    ~fo_formulas:summary_formulas ~ltl:[]

let lower_formula ~(node_name : ident) ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (f : Abs.summary_formula) : Abs.summary_formula =
  match Pre_k_lowering.lower_fo_formula_temporal_bindings ~temporal_bindings f.logic with
  | None ->
      failwith
        (Printf.sprintf
           "temporal_lower: unable to lower formula for node %s: %s"
           node_name (Pretty.string_of_fo f.logic))
  | Some logic -> { f with logic = simplify_fo logic }

let run_node (node : Abs.node_ir) : Abs.node_ir =
  let temporal_layout = required_temporal_layout node in
  let temporal_bindings = Ir_formula.temporal_bindings_of_layout temporal_layout in
  let lower = lower_formula ~node_name:node.semantics.sem_nname ~temporal_bindings in
  let summaries =
    node.summaries
    |> List.map (fun (summary : Abs.product_step_summary) ->
           let propagation_requires = List.map lower summary.propagation_requires in
           let requires = List.map lower summary.requires in
           let ensures = List.map lower summary.ensures in
           let safe_cases =
             summary.safe_cases
             |> List.map (fun (c : Abs.safe_product_case) ->
                    { c with admissible_guard = lower c.admissible_guard })
           in
           let unsafe_cases =
             summary.unsafe_cases
             |> List.map (fun (c : Abs.unsafe_product_case) ->
                    { c with excluded_guard = lower c.excluded_guard })
           in
           { summary with propagation_requires; requires; ensures; safe_cases; unsafe_cases })
  in
  let init_invariant_goals = List.map lower node.init_invariant_goals in
  { node with temporal_layout; summaries; init_invariant_goals }

let run_program (program : Abs.node_ir list) : Abs.node_ir list =
  List.map run_node program
