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

module Abs = Ir
module Family = Obligation_family_projection
module Formula = Kernel_clause_projection_formula
module Summary = Product_summary_projection
module Transition_id = Kernel_clause_projection_transition_id

type time_tag =
  | PreviousTick
  | StepTickContext
  | CurrentTick

type timed_fact_desc =
  | FactProgramState of ident
  | FactGuaranteeState of int
  | FactPhaseFormula of hexpr
  | FactFormula of hexpr
  | FactFalse

type timed_fact = {
  tf_time : time_tag;
  tf_desc : timed_fact_desc;
}

type product_state_anchor = Summary.product_state_anchor

type product_step_anchor = {
  psta_src : product_state_anchor;
  psta_dst : product_state_anchor;
  psta_transition_id : string;
}

type product_step_class =
  | StepSafe
  | StepBadAssumption
  | StepBadGuarantee

type product_step = {
  step_anchor : product_step_anchor;
  program_guard : hexpr;
  assume_guard : hexpr;
  guarantee_guard : hexpr;
  step_class : product_step_class;
}

type anchor =
  | AnchorProductState of product_state_anchor
  | AnchorProductStep of product_step_anchor

type kernel_clause = {
  kc_anchor : anchor;
  kc_hypotheses : timed_fact list;
  kc_conclusions : timed_fact list;
}

type clause_context =
  | ClauseProductState of product_state_anchor
  | ClauseProductStep of product_step

type classified_clause = {
  family : Family.clause_family;
  context : clause_context;
  clause : kernel_clause;
}

let product_step_anchor (step : product_step) = step.step_anchor

let current tf_desc = { tf_time = CurrentTick; tf_desc }
let previous tf_desc = { tf_time = PreviousTick; tf_desc }
let step_ctx tf_desc = { tf_time = StepTickContext; tf_desc }

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let same_product_state = Summary.same_product_state

let same_safe_case_step (case : Abs.safe_product_case) (step : product_step) =
  step.step_class = StepSafe
  && same_product_state case.product_dst step.step_anchor.psta_dst
  && simplify_fo case.admissible_guard.logic = simplify_fo step.guarantee_guard

let same_unsafe_case_step (case : Abs.unsafe_product_case) (step : product_step) =
  step.step_class = StepBadGuarantee
  && same_product_state case.product_dst step.step_anchor.psta_dst
  && simplify_fo case.excluded_guard.logic = simplify_fo step.guarantee_guard

let product_summary_of_step ~(projection : Summary.t) (step : product_step) :
    Abs.product_step_summary option =
  match Transition_id.product_transition_index_of_id step.step_anchor.psta_transition_id with
  | None -> None
  | Some program_transition_id -> (
      Summary.find_by_identity projection ~program_transition_id
        ~product_src:step.step_anchor.psta_src ~assume_guard:step.assume_guard
      |> Option.map (fun summary -> summary.Summary.source_summary)
      |> function
      | None -> None
      | Some pc ->
          if
            match step.step_class with
            | StepSafe ->
                List.exists (fun case -> same_safe_case_step case step) pc.safe_cases
            | StepBadGuarantee ->
                List.exists (fun case -> same_unsafe_case_step case step) pc.unsafe_cases
            | StepBadAssumption -> false
          then Some pc
          else None)

let guarantee_propagation_requires (pc : Abs.product_step_summary) : hexpr list =
  List.map (fun (f : Abs.summary_formula) -> f.logic) pc.propagation_requires

let anchor_of_context = function
  | ClauseProductState state -> AnchorProductState state
  | ClauseProductStep step -> AnchorProductStep step.step_anchor

let mk_clause family context ~hypotheses ~conclusions =
  {
    family;
    context;
    clause =
      {
        kc_anchor = anchor_of_context context;
        kc_hypotheses = hypotheses;
        kc_conclusions = conclusions;
      };
  }

let product_summaries_of_step ~projection step =
  match product_summary_of_step ~projection step with
  | None -> []
  | Some pc -> [ pc ]

let build_source_summary_clauses ~(node : Abs.node_ir) ~(steps : product_step list) :
    classified_clause list =
  let projection = Summary.of_ir_node node in
  let input_names =
    Fo_current_input.input_names node.semantics.sem_inputs
  in
  let reject_current_inputs_in_source_summary f =
    Fo_current_input.require_no_current_input
      ~context:"kernel_clause_projection: source product summaries"
      ~input_names f
  in
  let all_states =
    steps
    |> List.concat_map (fun step -> [ step.step_anchor.psta_src; step.step_anchor.psta_dst ])
    |> List.sort_uniq Stdlib.compare
  in
  let source_summaries =
    all_states
    |> List.filter_map (fun st ->
           let formulas =
             steps
             |> List.filter (fun step ->
                    same_product_state step.step_anchor.psta_src st
                    && step.step_class = StepSafe)
             |> List.concat_map (product_summaries_of_step ~projection)
             |> List.concat_map guarantee_propagation_requires
             |> List.map reject_current_inputs_in_source_summary
             |> List.sort_uniq Stdlib.compare
           in
           let phase_formula =
             match formulas with
             | [] -> None
             | f :: rest ->
                 Some
                   (List.fold_left Core_syntax_builders.mk_hor f rest
                   |> Formula.normalize_source_summary)
           in
           match phase_formula with
           | None -> None
           | Some phase_formula ->
               if Formula.phase_summary_obviously_inconsistent phase_formula then None
               else
                 Some
                   (mk_clause Family.SourceProductSummary
                      (ClauseProductState st)
                      ~hypotheses:
                        [
                          current (FactProgramState st.prog_state);
                          current (FactGuaranteeState st.guarantee_state_index);
                        ]
                      ~conclusions:
                        [
                          current (FactPhaseFormula phase_formula);
                          current (FactFormula phase_formula);
                        ]))
  in
  let phase_formula_of_clause classified =
    classified.clause.kc_conclusions
    |> List.find_map (fun fact ->
           match (fact.tf_time, fact.tf_desc) with
           | CurrentTick, FactPhaseFormula phase_formula -> Some phase_formula
           | _ -> None)
  in
  let state_of_context classified =
    match classified.context with
    | ClauseProductState st -> Some st
    | ClauseProductStep _ -> None
  in
  let raw_formula_table = Hashtbl.create 16 in
  List.iter
    (fun clause ->
      match (state_of_context clause, phase_formula_of_clause clause) with
      | Some st, Some phase_formula ->
          let key = (st.prog_state, st.guarantee_state_index) in
          let merged =
            match Hashtbl.find_opt raw_formula_table key with
            | None -> phase_formula
            | Some prev -> Formula.term_or prev phase_formula
          in
          Hashtbl.replace raw_formula_table key merged
      | _ -> ())
    source_summaries;
  let by_prog_state = Hashtbl.create 16 in
  Hashtbl.iter
    (fun ((prog_state, _gidx) as key) phase_formula ->
      let prev = Hashtbl.find_opt by_prog_state prog_state |> Option.value ~default:[] in
      Hashtbl.replace by_prog_state prog_state ((snd key, phase_formula, key) :: prev))
    raw_formula_table;
  let exclusive_formula_table = Hashtbl.create 16 in
  Hashtbl.iter
    (fun _prog_state entries ->
      let entries = List.sort (fun (g1, _, _) (g2, _, _) -> Int.compare g1 g2) entries in
      let _covered, () =
        List.fold_left
          (fun (covered_opt, ()) (_gidx, raw_fo, key) ->
            let exclusive =
              match covered_opt with
              | None -> raw_fo
              | Some covered -> Formula.term_and raw_fo (Formula.term_not covered)
            in
            Hashtbl.replace exclusive_formula_table key
              (Formula.normalize_source_summary exclusive);
            let covered_opt =
              match covered_opt with
              | None -> Some raw_fo
              | Some covered -> Some (Formula.term_or covered raw_fo)
            in
            (covered_opt, ()))
          (None, ()) entries
      in
      ())
    by_prog_state;
  source_summaries
  |> List.map (fun classified ->
         match state_of_context classified with
         | None -> classified
         | Some st -> (
             let key = (st.prog_state, st.guarantee_state_index) in
             match Hashtbl.find_opt exclusive_formula_table key with
             | Some phase_formula
               when not (Formula.phase_summary_obviously_inconsistent phase_formula) ->
                 {
                   classified with
                   clause =
                     {
                       classified.clause with
                       kc_conclusions =
                         [
                           current (FactPhaseFormula phase_formula);
                           current (FactFormula phase_formula);
                         ];
                     };
                 }
             | _ -> classified))

let compatibility_phase_formula_for_step ~projection step =
  match product_summary_of_step ~projection step with
  | None -> None
  | Some pc -> (
      guarantee_propagation_requires pc
      |> List.sort_uniq Stdlib.compare
      |> function
      | [] -> None
      | f :: rest ->
          Some
            (List.fold_left Core_syntax_builders.mk_hor f rest
            |> Formula.normalize_phase_summary))

let invariant_formulas_for_state (node : Abs.node_ir) state_name =
  node.source_info.state_invariants
  |> List.filter_map (fun (inv : Abs.state_invariant) ->
         if String.equal inv.state state_name then Some inv.formula else None)

let invariant_facts_for_state node state_name =
  invariant_formulas_for_state node state_name
  |> List.map (fun formula -> current (FactFormula formula))

let build ~(node : Abs.node_ir) ~(initial_state : product_state_anchor)
    ~(steps : product_step list) ~is_live_state : classified_clause list =
  let projection = Summary.of_ir_node node in
  let init_goal_facts =
    node.init_invariant_goals
    |> List.map (fun (f : Abs.summary_formula) -> current (FactFormula f.logic))
  in
  let init_clauses =
    [
      mk_clause Family.InitNodeInvariant
        (ClauseProductState initial_state)
        ~hypotheses:[ current (FactProgramState initial_state.prog_state) ]
        ~conclusions:
          (current (FactProgramState initial_state.prog_state) :: init_goal_facts);
      mk_clause Family.InitAutomatonCoherence
        (ClauseProductState initial_state)
        ~hypotheses:[ current (FactProgramState initial_state.prog_state) ]
        ~conclusions:[ current (FactGuaranteeState initial_state.guarantee_state_index) ];
    ]
  in
  let source_summary_clauses = build_source_summary_clauses ~node ~steps in
  let step_clauses =
    List.concat_map
      (fun step ->
        let step_context = ClauseProductStep step in
        let src = step.step_anchor.psta_src in
        let dst = step.step_anchor.psta_dst in
        let propagation =
          if is_live_state src then
            let base_hypotheses =
              [
                previous (FactProgramState src.prog_state);
                previous (FactGuaranteeState src.guarantee_state_index);
                step_ctx (FactFormula step.program_guard);
                step_ctx (FactFormula step.assume_guard);
              ]
            in
            let phase_clause =
              [
                mk_clause Family.PhaseStepSummary step_context
                  ~hypotheses:base_hypotheses
                  ~conclusions:[ current (FactPhaseFormula step.guarantee_guard) ];
              ]
            in
            let phase_pre_clause =
              match compatibility_phase_formula_for_step ~projection step with
              | None -> []
              | Some phase_formula ->
                  [
                    mk_clause Family.PhaseStepPreSummary step_context
                      ~hypotheses:
                        [
                          previous (FactProgramState src.prog_state);
                          previous (FactGuaranteeState src.guarantee_state_index);
                        ]
                      ~conclusions:[ previous (FactPhaseFormula phase_formula) ];
                  ]
            in
            [
              mk_clause Family.PropagationNodeInvariant step_context
                ~hypotheses:base_hypotheses
                ~conclusions:
                  (current (FactProgramState dst.prog_state)
                  :: invariant_facts_for_state node dst.prog_state);
              mk_clause Family.PropagationAutomatonCoherence step_context
                ~hypotheses:base_hypotheses
                ~conclusions:[ current (FactGuaranteeState dst.guarantee_state_index) ];
            ]
            @ phase_pre_clause @ phase_clause
          else []
        in
        let safety =
          match step.step_class with
          | StepBadGuarantee ->
              Formula.split_top_level_or step.guarantee_guard
              |> List.map (fun bad_case ->
                     mk_clause Family.Safety step_context
                       ~hypotheses:
                         [
                           previous (FactProgramState src.prog_state);
                           previous (FactGuaranteeState src.guarantee_state_index);
                           step_ctx (FactFormula step.program_guard);
                           step_ctx (FactFormula step.assume_guard);
                           step_ctx (FactFormula bad_case);
                         ]
                       ~conclusions:[ current FactFalse ])
          | StepSafe | StepBadAssumption -> []
        in
        propagation @ safety)
      steps
  in
  init_clauses @ source_summary_clauses @ step_clauses
