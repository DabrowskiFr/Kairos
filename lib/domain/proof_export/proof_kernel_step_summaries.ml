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

(** Proof-step summary synthesis for proof-kernel export.

    This module groups product steps by canonical summary identity while
    preserving the relational historical formulas produced before temporal
    lowering. *)

open Core_syntax
open Core_syntax_builders

(** Module [Abs]. *)

module Abs = Ir
module K = Kernel_clause_projection
open Proof_kernel_types
open Obligation_family_projection

(** [simplify_fo] helper value. *)

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let product_state_ref_of_ir (st : product_state_ir) : Abs.product_state =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state_index;
    guarantee_state_index = st.guarantee_state_index;
  }

(** [build_proof_step_summaries] helper value. *)

let build_proof_step_summaries ~(node : Abs.node_ir) ~(reactive_program : reactive_program_ir)
    ~(product_steps : product_step_ir list)
    ~(initial_product_state : product_state_ir)
    ~(symbolic_generated_clauses : relational_generated_clause_ir list) :
    proof_step_summary_ir list =
  let _ = initial_product_state in
  let transition_index_by_id =
    reactive_program.transitions
    |> List.mapi (fun idx (tr : reactive_transition_ir) -> (tr.transition_id, idx))
    |> List.to_seq |> Hashtbl.of_seq
  in
  let product_summary_projection =
    Product_summary_projection.of_ir_node node
  in
  let product_summary_of_step (step : product_step_ir) : Abs.product_step_summary option =
    match Hashtbl.find_opt transition_index_by_id step.program_transition_id with
    | None -> None
    | Some step_uid ->
        Product_summary_projection.find_by_identity product_summary_projection
          ~program_transition_id:step_uid
          ~product_src:(product_state_ref_of_ir step.src)
          ~assume_guard:step.assume_edge.guard
        |> Option.map (fun summary -> summary.Product_summary_projection.source_summary)
  in
  let is_true_fo (f : Core_syntax.hexpr) =
    match f.hexpr with HLitBool true -> true | _ -> false
  in
  let relational_fact_is_true (fact : relational_clause_fact_ir) =
    match fact.desc with
    | RelFactFormula h | RelFactPhaseFormula h -> is_true_fo h
    | RelFactFalse | RelFactProgramState _ | RelFactGuaranteeState _ -> false
  in
  let normalize_relational_clause (clause : relational_generated_clause_ir) =
    let hypotheses =
      List.filter (fun fact -> not (relational_fact_is_true fact)) clause.hypotheses
    in
    let conclusions =
      List.filter (fun fact -> not (relational_fact_is_true fact)) clause.conclusions
    in
    match conclusions with [] -> None | _ -> Some { clause with hypotheses; conclusions }
  in
  let is_structural_step_fact (fact : relational_clause_fact_ir) =
    match fact.desc with
    | RelFactProgramState _ | RelFactGuaranteeState _ -> true
    | _ -> false
  in
  let strip_structural_step_facts (clause : relational_generated_clause_ir) :
      relational_generated_clause_ir =
    {
      clause with
      hypotheses = List.filter (fun fact -> not (is_structural_step_fact fact)) clause.hypotheses;
      conclusions = List.filter (fun fact -> not (is_structural_step_fact fact)) clause.conclusions;
    }
  in
  let raw_clauses_for_step (step : product_step_ir) =
    symbolic_generated_clauses
    |> List.filter (fun (clause : relational_generated_clause_ir) ->
           match (clause.family, clause.anchor) with
           | PhaseStepPreSummary, _ -> false
           | _, K.ClauseProductStep anchored_step ->
               Proof_kernel_clause_context.same_product_step anchored_step step
           | _, K.ClauseProductState _ -> false)
    |> List.map strip_structural_step_facts
  in
  let clauses_for_step (step : product_step_ir) =
    raw_clauses_for_step step
    |> List.filter_map normalize_relational_clause
  in
  let entry_clauses_for_steps (steps : product_step_ir list) =
    match steps with
    | [] -> []
    | step :: _ -> (
        match product_summary_of_step step with
        | None -> []
        | Some pc ->
            pc.requires
            |> List.filter_map (fun (f : Ir.summary_formula) ->
                   let logic = simplify_fo f.logic in
                   if is_true_fo logic then None
                   else
                     Some
                      {
                        family = PhaseStepPreSummary;
                        anchor =
                          K.ClauseProductStep
                            (Proof_kernel_clause_context.product_step_to_kernel step);
                        hypotheses = [];
                        conclusions =
                          [ { time = K.CurrentTick; desc = RelFactFormula logic } ];
                      }))
  in
  let dedup_clauses (clauses : relational_generated_clause_ir list) =
    List.sort_uniq Stdlib.compare clauses
  in
  let safe_group_key (step : product_step_ir) =
    (step.program_transition_id, step.src, step.assume_edge)
  in
  let safe_groups = Hashtbl.create 16 in
  let safe_order = ref [] in
  let singleton_summary step =
    let steps = [ step ] in
    let entry_clauses = entry_clauses_for_steps steps in
    let clauses = clauses_for_step step in
    { steps; entry_clauses; clauses }
  in
  let summaries_rev = ref [] in
  List.iter
    (fun (step : product_step_ir) ->
      match step.step_kind with
      | StepSafe ->
          let key = safe_group_key step in
          if not (Hashtbl.mem safe_groups key) then safe_order := key :: !safe_order;
          let prev = Hashtbl.find_opt safe_groups key |> Option.value ~default:[] in
          Hashtbl.replace safe_groups key (step :: prev)
      | StepBadAssumption | StepBadGuarantee -> summaries_rev := singleton_summary step :: !summaries_rev)
    product_steps;
  let safe_summaries =
    List.rev !safe_order
    |> List.map (fun key ->
           let steps = Hashtbl.find safe_groups key |> List.rev in
           let entry_clauses = entry_clauses_for_steps steps in
           let clauses = steps |> List.concat_map clauses_for_step |> dedup_clauses in
           { steps; entry_clauses; clauses })
  in
  safe_summaries @ List.rev !summaries_rev
