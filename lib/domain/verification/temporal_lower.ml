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

let simplify_history_free
    (formula : Core_syntax.history_free Core_syntax.hexpr) :
    Core_syntax.history_free Core_syntax.hexpr =
  let simplified =
    formula |> Core_syntax.historical_of_history_free
    |> Core_fo_simplifier.simplify
  in
  match Core_syntax.history_free_of_historical simplified with
  | Some formula -> formula
  | None ->
      invalid_arg "first-order simplification introduced historical syntax"

let required_temporal_layout (node : Core_syntax.historical Abs.node_ir) : Abs.temporal_layout =
  let summary_formulas =
    let product_formulas =
      node.summaries
      |> List.concat_map (fun (summary : Core_syntax.historical Abs.product_step_summary) ->
             summary.identity.assume_guard
             :: (Ir_formula.values
                   (summary.propagation_requires @ summary.requires
                  @ summary.ensures @ summary.elaboration_checks)
             @
             let case_formulas =
               List.concat_map
                 (fun (case : Core_syntax.historical Abs.safe_product_case) -> [ case.admissible_guard ])
                 summary.safe_cases
               @ List.concat_map
                   (fun (case : Core_syntax.historical Abs.unsafe_product_case) -> [ case.excluded_guard ])
                   summary.unsafe_cases
             in
             Ir_formula.values case_formulas))
    in
    product_formulas @ Ir_formula.values node.init_invariant_goals
  in
  Pre_k_layout.build_pre_k_infos_from_parts ~inputs:node.semantics.sem_inputs
    ~locals:node.semantics.sem_locals ~outputs:node.semantics.sem_outputs
    ~fo_formulas:summary_formulas ~ltl:[]

let run_node (node : Core_syntax.historical Abs.node_ir) :
    Core_syntax.history_free Abs.node_ir =
  let temporal_layout = required_temporal_layout node in
  let temporal_bindings = Ir_formula.temporal_bindings_of_layout temporal_layout in
  let lower_logic
      (input : Core_syntax.historical Core_syntax.hexpr) =
    match
      Pre_k_lowering.lower_fo_formula_temporal_bindings
        ~temporal_bindings input
    with
    | Some logic -> simplify_history_free logic
    | None ->
        failwith
          (Printf.sprintf
             "temporal_lower: unable to lower formula for node %s: %s"
             node.semantics.sem_nname
             (Pretty.string_of_fo input))
  in
  let lower (formula : Core_syntax.historical Abs.summary_formula) :
      Core_syntax.history_free Abs.summary_formula =
    { logic = lower_logic formula.logic; meta = formula.meta }
  in
  let summaries =
    node.summaries
    |> List.map (fun (summary : Core_syntax.historical Abs.product_step_summary) ->
           let propagation_requires = List.map lower summary.propagation_requires in
           let requires = List.map lower summary.requires in
           let ensures = List.map lower summary.ensures in
           let elaboration_checks = List.map lower summary.elaboration_checks in
           let safe_cases =
             summary.safe_cases
             |> List.map (fun (c : Core_syntax.historical Abs.safe_product_case) ->
                    {
                      Abs.product_dst = c.product_dst;
                      admissible_guard = lower c.admissible_guard;
                    })
           in
           let unsafe_cases =
             summary.unsafe_cases
             |> List.map (fun (c : Core_syntax.historical Abs.unsafe_product_case) ->
                    {
                      Abs.product_dst = c.product_dst;
                      excluded_guard = lower c.excluded_guard;
                    })
           in
           {
             Abs.trace = summary.trace;
             identity =
               {
                 Abs.program_step = summary.identity.program_step;
                 product_src = summary.identity.product_src;
                 assume_guard = lower_logic summary.identity.assume_guard;
               };
             propagation_requires;
             requires;
             ensures;
             elaboration_checks;
             safe_cases;
             unsafe_cases;
           })
  in
  let init_invariant_goals = List.map lower node.init_invariant_goals in
  {
    Abs.semantics = node.semantics;
    source_info = node.source_info;
    temporal_layout;
    summaries;
    init_invariant_goals;
  }

let run_program
    (program : Core_syntax.historical Abs.node_ir list) :
    Core_syntax.history_free Abs.node_ir list =
  List.map run_node program
