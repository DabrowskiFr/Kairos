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

    This module groups product steps by canonical summary identity and rewrites
    pre/post formulas according to temporal layout slots. *)

open Core_syntax
open Core_syntax_builders

(** Module [Abs]. *)

module Abs = Ir
open Proof_kernel_types

(** [simplify_fo] helper value. *)

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr = f

(** [same_product_state] helper value. *)

let same_product_state (a : Abs.product_state) (b : product_state_ir) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

(** [build_proof_step_summaries] helper value. *)

let build_proof_step_summaries ~(node : Abs.node_ir) ~(reactive_program : reactive_program_ir)
    ~(product_steps : product_step_ir list)
    ~(temporal_layout : Ir.temporal_layout)
    ~(initial_product_state : product_state_ir)
    ~(symbolic_generated_clauses : relational_generated_clause_ir list) :
    proof_step_summary_ir list =
  let _ = initial_product_state in
  let transition_index_by_id =
    reactive_program.transitions
    |> List.mapi (fun idx (tr : reactive_transition_ir) -> (tr.transition_id, idx))
    |> List.to_seq |> Hashtbl.of_seq
  in
  let product_summary_of_step (step : product_step_ir) : Abs.product_step_summary option =
    match Hashtbl.find_opt transition_index_by_id step.program_transition_id with
    | None -> None
    | Some step_uid ->
        List.find_opt
          (fun (pc : Abs.product_step_summary) ->
            pc.trace.step_uid = step_uid
            && same_product_state pc.identity.product_src step.src
            && simplify_fo pc.identity.assume_guard = simplify_fo step.assume_edge.guard)
          node.summaries
  in
  let slot_to_current_expr =
    let add acc (info : Pre_k_layout.pre_k_info) =
      info.Pre_k_layout.names
      |> List.mapi (fun idx name ->
             let lowered =
               if idx = 0 then Core_syntax_builders.mk_hvar info.Pre_k_layout.var_name
               else Core_syntax_builders.mk_hpre_k info.Pre_k_layout.var_name idx
             in
             (name, lowered))
      |> List.rev_append acc
    in
    List.fold_left add [] temporal_layout
  in
  let current_expr_to_next_slot =
    let add acc (info : Pre_k_layout.pre_k_info) =
      (info.Pre_k_layout.var_name, info.Pre_k_layout.names) :: acc
    in
    List.fold_left add [] temporal_layout
  in
  let rec rewrite_hexpr_post (h : hexpr) : hexpr =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HPreK _ -> h
    | HVar name -> (
        match List.assoc_opt name slot_to_current_expr with
        | Some lowered -> lowered
        | None -> h)
    | HUn (op, inner) ->
        Core_syntax_builders.with_hexpr_desc h (HUn (op, rewrite_hexpr_post inner))
    | HPred (id, hs) ->
        Core_syntax_builders.with_hexpr_desc h (HPred (id, List.map rewrite_hexpr_post hs))
    | HBin (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h
          (HBin (op, rewrite_hexpr_post a, rewrite_hexpr_post b))
    | HCmp (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h (HCmp (op, rewrite_hexpr_post a, rewrite_hexpr_post b))
  in
  let rec rewrite_formula_post (f : Core_syntax.hexpr) : Core_syntax.hexpr =
    match f.hexpr with
    | HLitInt _ | HLitBool _ | HVar _ | HPreK _ -> rewrite_hexpr_post f
    | HPred _ | HUn _ | HBin _ | HCmp _ -> rewrite_hexpr_post f
  in
  let slot_name_for_depth base_var depth =
    match List.assoc_opt base_var current_expr_to_next_slot with
    | None -> None
    | Some names ->
        let idx = depth - 1 in
        if idx < 0 || idx >= List.length names then None else Some (List.nth names idx)
  in
  let rec rewrite_hexpr_pre (h : hexpr) : hexpr =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar name -> (
        match slot_name_for_depth name 1 with
        | Some slot -> Core_syntax_builders.mk_hvar slot
        | None -> h)
    | HPreK (name, k) -> (
        match slot_name_for_depth name (k + 1) with
        | Some slot -> Core_syntax_builders.mk_hvar slot
        | None -> h)
    | HPred (id, hs) ->
        Core_syntax_builders.with_hexpr_desc h (HPred (id, List.map rewrite_hexpr_pre hs))
    | HUn (op, inner) ->
        Core_syntax_builders.with_hexpr_desc h (HUn (op, rewrite_hexpr_pre inner))
    | HBin (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h
          (HBin (op, rewrite_hexpr_pre a, rewrite_hexpr_pre b))
    | HCmp (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h (HCmp (op, rewrite_hexpr_pre a, rewrite_hexpr_pre b))
  in
  let rec rewrite_formula_pre (f : Core_syntax.hexpr) : Core_syntax.hexpr =
    match f.hexpr with
    | HLitInt _ | HLitBool _ | HVar _ | HPreK _ -> rewrite_hexpr_pre f
    | HPred _ | HUn _ | HBin _ | HCmp _ -> rewrite_hexpr_pre f
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
           match (clause.origin, clause.anchor) with
           | OriginPhaseStepPreSummary, _ -> false
           | _, ClauseAnchorProductStep anchored_step -> anchored_step = step
           | _, ClauseAnchorProductState _ -> false)
    |> List.map strip_structural_step_facts
  in
  let shift_post_fact (fact : relational_clause_fact_ir) =
    let desc =
      match fact.desc with
      | RelFactPhaseFormula fo_formula -> RelFactPhaseFormula (rewrite_formula_post fo_formula)
      | RelFactFormula fo_formula -> RelFactFormula (rewrite_formula_post fo_formula)
      | _ -> fact.desc
    in
    { fact with desc }
  in
  let clauses_for_step (step : product_step_ir) =
    raw_clauses_for_step step
    |> List.map (fun clause ->
           match clause.origin with
           | OriginPropagationNodeInvariant ->
               {
                 clause with
                 hypotheses = List.map shift_post_fact clause.hypotheses;
                 conclusions = List.map shift_post_fact clause.conclusions;
               }
           | OriginPropagationAutomatonCoherence
           | OriginPhaseStepSummary
           | OriginSafety
           | OriginSourceProductSummary
           | OriginPhaseStepPreSummary
           | OriginInitNodeInvariant
           | OriginInitAutomatonCoherence ->
               clause)
  in
  let entry_clauses_for_steps (steps : product_step_ir list) =
    match steps with
    | [] -> []
    | step :: _ -> (
    match product_summary_of_step step with
        | None -> []
        | Some pc ->
            pc.requires
            |> List.map (fun (f : Ir.summary_formula) ->
                   {
                     origin = OriginPhaseStepPreSummary;
                     anchor = ClauseAnchorProductStep step;
                     hypotheses = [];
                     conclusions =
                       [
                         {
                           time = CurrentTick;
                           desc =
                             RelFactFormula
                               (simplify_fo (rewrite_formula_pre f.logic));
                         };
                       ];
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
