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

(** Construction of generated clauses from canonical summaries and product data.

    This module derives source-level, phase and safety clauses before
    relational lowering. *)

(** Construction of generated clauses from canonical summaries and product data. *)

open Core_syntax

module Abs = Ir
module PT = Product_types
open Proof_kernel_types

let build_source_summary_clauses =
  Proof_kernel_source_clauses.build_source_summary_clauses

let build_generated_clauses ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    ~(initial_state : product_state_ir) ~(steps : product_step_ir list) ~automaton_guard_fo
    ~is_live_state : generated_clause_ir list =
  let current (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc } in
  let previous (desc : clause_fact_desc_ir) : clause_fact_ir = { time = PreviousTick; desc } in
  let step_ctx (desc : clause_fact_desc_ir) : clause_fact_ir = { time = StepTickContext; desc } in
  let guarantee_propagation_requires (pc : Abs.product_step_summary) : Core_syntax.hexpr list =
    List.map (fun (f : Abs.summary_formula) -> f.logic) pc.propagation_requires
  in
  let rec split_top_level_or (f : Core_syntax.hexpr) : Core_syntax.hexpr list =
    match f.hexpr with
    | HBin (Or, a, b) -> split_top_level_or a @ split_top_level_or b
    | _ -> [ f ]
  in
  let rec normalize_phase_summary (f : Core_syntax.hexpr) : Core_syntax.hexpr =
    match f.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HPred _ -> f
    | HFunCall (fn, hs) ->
        Core_syntax_builders.with_hexpr_desc f
          (HFunCall (fn, List.map normalize_phase_summary hs))
    | HUn (op, inner) ->
        Core_syntax_builders.with_hexpr_desc f (HUn (op, normalize_phase_summary inner))
    | HBin (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc f
          (HBin (op, normalize_phase_summary a, normalize_phase_summary b))
    | HCmp (r, a, b) ->
        Core_syntax_builders.with_hexpr_desc f
          (HCmp (r, normalize_phase_summary a, normalize_phase_summary b))
  in
  let compatibility_phase_formula_for_step (step : product_step_ir) =
    match Proof_kernel_product_lookup.product_summary_of_step ~node step with
    | None -> None
    | Some pc ->
        guarantee_propagation_requires pc
        |> List.sort_uniq Stdlib.compare
        |> function
        | [] -> None
        | f :: rest ->
            Some
              (List.fold_left Core_syntax_builders.mk_hor f rest
              |> normalize_phase_summary)
  in
  let invariants_for_state state_name =
    node.source_info.state_invariants
    |> List.filter_map (fun (inv : Ir.state_invariant) ->
           if inv.state = state_name then Some (current (FactFormula inv.formula))
           else None)
  in
  let init_goal_facts =
    node.init_invariant_goals
    |> List.map (fun (f : Abs.summary_formula) -> current (FactFormula f.logic))
  in
  let init_clauses =
    [
      ({
        origin = OriginInitNodeInvariant;
        anchor = ClauseAnchorProductState initial_state;
        hypotheses = [ current (FactProgramState initial_state.prog_state) ];
        conclusions = current (FactProgramState initial_state.prog_state) :: init_goal_facts;
      } : generated_clause_ir);
      ({
        origin = OriginInitAutomatonCoherence;
        anchor = ClauseAnchorProductState initial_state;
        hypotheses = [ current (FactProgramState initial_state.prog_state) ];
        conclusions = [ current (FactGuaranteeState initial_state.guarantee_state_index) ];
      } : generated_clause_ir);
    ]
  in
  let source_summary_clauses =
    Proof_kernel_source_clauses.build_source_summary_clauses ~node ~analysis ~steps
      ~automaton_guard_fo
  in
  let step_clauses =
    List.concat_map
      (fun step ->
        let src_live =
          is_live_state ~analysis
            {
              PT.prog_state = step.src.prog_state;
              assume_state = step.src.assume_state_index;
              guarantee_state = step.src.guarantee_state_index;
            }
        in
        let propagation =
          if src_live then
            let base_hypotheses =
              [
                previous (FactProgramState step.src.prog_state);
                previous (FactGuaranteeState step.src.guarantee_state_index);
                step_ctx (FactFormula step.program_guard);
                step_ctx (FactFormula step.assume_edge.guard);
              ]
            in
            let phase_clause =
              [
                ({
                  origin = OriginPhaseStepSummary;
                  anchor = ClauseAnchorProductStep step;
                  hypotheses = base_hypotheses;
                  conclusions = [ current (FactPhaseFormula step.guarantee_edge.guard) ];
                } : generated_clause_ir);
              ]
            in
            let phase_pre_clause =
              match compatibility_phase_formula_for_step step with
              | None -> []
              | Some phase_formula ->
                  [
                    ({
                      origin = OriginPhaseStepPreSummary;
                      anchor = ClauseAnchorProductStep step;
                      hypotheses =
                        [
                          previous (FactProgramState step.src.prog_state);
                          previous (FactGuaranteeState step.src.guarantee_state_index);
                        ];
                      conclusions = [ previous (FactPhaseFormula phase_formula) ];
                    } : generated_clause_ir);
                  ]
            in
            [
              ({
                origin = OriginPropagationNodeInvariant;
                anchor = ClauseAnchorProductStep step;
                hypotheses = base_hypotheses;
                conclusions = current (FactProgramState step.dst.prog_state) :: invariants_for_state step.dst.prog_state;
              } : generated_clause_ir);
              ({
                origin = OriginPropagationAutomatonCoherence;
                anchor = ClauseAnchorProductStep step;
                hypotheses = base_hypotheses;
                conclusions = [ current (FactGuaranteeState step.dst.guarantee_state_index) ];
              } : generated_clause_ir);
            ]
            @ phase_pre_clause @ phase_clause
          else []
        in
        let safety =
          match step.step_kind with
          | StepBadGuarantee ->
              split_top_level_or step.guarantee_edge.guard
              |> List.map (fun bad_case ->
                     ({
                       origin = OriginSafety;
                       anchor = ClauseAnchorProductStep step;
                       hypotheses =
                         [
                           previous (FactProgramState step.src.prog_state);
                           previous (FactGuaranteeState step.src.guarantee_state_index);
                           step_ctx (FactFormula step.program_guard);
                           step_ctx (FactFormula step.assume_edge.guard);
                           step_ctx (FactFormula bad_case);
                         ];
                       conclusions = [ current FactFalse ];
                     } : generated_clause_ir))
          | StepSafe | StepBadAssumption -> []
        in
        propagation @ safety)
      steps
  in
  init_clauses @ source_summary_clauses @ step_clauses
