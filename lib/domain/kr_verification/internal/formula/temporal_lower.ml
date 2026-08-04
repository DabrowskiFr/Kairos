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
open Kr_domain_core_syntax

module Abs = Kr_verification_ir

let simplify_history_free
    (formula : Kr_domain_core_syntax.history_free Kr_domain_core_syntax.hexpr) :
    Kr_domain_core_syntax.history_free Kr_domain_core_syntax.hexpr =
  let simplified =
    formula |> Kr_domain_core_syntax.historical_of_history_free
    |> Kr_domain_core_formula_simplifier.simplify
  in
  match Kr_domain_core_syntax.history_free_of_historical simplified with
  | Some formula -> formula
  | None ->
      invalid_arg "first-order simplification introduced historical syntax"

let required_temporal_layout (node : Kr_domain_core_syntax.historical Abs.node_ir) : Abs.temporal_layout =
  let summary_formulas =
    node.summaries
    |> List.concat_map (fun (summary : Kr_domain_core_syntax.historical Abs.product_step_summary) ->
           summary.identity.assume_guard
           :: (Ir_formula.values
                 (summary.propagation_requires @ summary.requires
                @ summary.ensures @ summary.elaboration_checks)
           @
           let case_formulas =
             List.concat_map
               (fun (case : Kr_domain_core_syntax.historical Abs.product_case) ->
                 [ case.guarantee_guard ])
               summary.product_cases
           in
           Ir_formula.values case_formulas))
  in
  Kr_domain_core.Kr_domain_core_history.build_pre_k_infos_from_parts ~inputs:node.semantics.sem_inputs
    ~locals:node.semantics.sem_locals ~outputs:node.semantics.sem_outputs
    ~fo_formulas:summary_formulas ~ltl:[]

let run_node (node : Kr_domain_core_syntax.historical Abs.node_ir) :
    Kr_domain_core_syntax.history_free Abs.node_ir =
  let temporal_layout = required_temporal_layout node in
  let temporal_bindings = Ir_formula.temporal_bindings_of_layout temporal_layout in
  let lower_logic
      (input : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) =
    match
      Kr_domain_core.Kr_domain_core_history.lower_fo_formula_temporal_bindings
        ~temporal_bindings input
    with
    | Some logic -> simplify_history_free logic
    | None ->
        failwith
          (Printf.sprintf
             "temporal_lower: unable to lower formula for node %s: %s"
             node.semantics.sem_nname
             (Kr_domain_render.Kr_domain_render_syntax.string_of_fo input))
  in
  let lower (formula : Kr_domain_core_syntax.historical Abs.summary_formula) :
      Kr_domain_core_syntax.history_free Abs.summary_formula =
    { logic = lower_logic formula.logic; meta = formula.meta }
  in
  let summaries =
    node.summaries
    |> List.map (fun (summary : Kr_domain_core_syntax.historical Abs.product_step_summary) ->
           let propagation_requires = List.map lower summary.propagation_requires in
           let requires = List.map lower summary.requires in
           let ensures = List.map lower summary.ensures in
           let elaboration_checks = List.map lower summary.elaboration_checks in
           let product_cases =
             summary.product_cases
             |> List.map (fun (c : Kr_domain_core_syntax.historical Abs.product_case) ->
                    {
                      Abs.guarantee_destination_state_index =
                        c.guarantee_destination_state_index;
                      guarantee_guard = lower c.guarantee_guard;
                    })
           in
           {
             Abs.trace = summary.trace;
             identity =
               {
                 Abs.program_step = summary.identity.program_step;
                 monitor_source = summary.identity.monitor_source;
                 assume_destination_state_index =
                   summary.identity
                     .assume_destination_state_index;
                 assume_guard = lower_logic summary.identity.assume_guard;
               };
             propagation_requires;
             requires;
             ensures;
             elaboration_checks;
             product_cases;
           })
  in
  {
    Abs.semantics = node.semantics;
    source_info = node.source_info;
    temporal_layout;
    summaries;
  }

let run_program
    (program : Kr_domain_core_syntax.historical Abs.node_ir list) :
    Kr_domain_core_syntax.history_free Abs.node_ir list =
  List.map run_node program
