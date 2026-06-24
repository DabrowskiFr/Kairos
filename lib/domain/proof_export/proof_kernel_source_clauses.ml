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

(** Source-summary clauses derived from canonical product summaries. *)

open Core_syntax

module Abs = Ir
open Proof_kernel_types

let build_source_summary_clauses ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    ~(steps : product_step_ir list) ~automaton_guard_fo : generated_clause_ir list =
  let _analysis = analysis in
  let _automaton_guard_fo = automaton_guard_fo in
  let current (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc } in
  let product_summaries_of_step (step : product_step_ir) : Abs.product_step_summary list =
    match Proof_kernel_product_lookup.product_summary_of_step ~node step with
    | None -> []
    | Some pc -> [ pc ]
  in
  let guarantee_propagation_requires (pc : Abs.product_step_summary) : Core_syntax.hexpr list =
    List.map (fun (f : Abs.summary_formula) -> f.logic) pc.propagation_requires
  in
  let input_names =
    node.semantics.sem_inputs
    |> List.map (fun (v : vdecl) -> v.vname)
    |> List.sort_uniq String.compare
  in
  let rec hexpr_mentions_current_input (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ | HPreK _ -> false
    | HVar name -> List.mem name input_names
    | HPred (_, hs) -> List.exists hexpr_mentions_current_input hs
    | HFunCall (_, hs) -> List.exists hexpr_mentions_current_input hs
    | HUn (_, inner) -> hexpr_mentions_current_input inner
    | HBin (_, a, b) | HCmp (_, a, b) ->
        hexpr_mentions_current_input a || hexpr_mentions_current_input b
  in
  let fo_mentions_current_input (f : Core_syntax.hexpr) =
    hexpr_mentions_current_input f
  in
  let rec normalize_source_summary (f : Core_syntax.hexpr) : Core_syntax.hexpr =
    match f.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HPred _ -> f
    | HFunCall (fn, hs) ->
        Core_syntax_builders.with_hexpr_desc f
          (HFunCall (fn, List.map normalize_source_summary hs))
    | HUn (Neg, inner) ->
        Core_syntax_builders.with_hexpr_desc f (HUn (Neg, normalize_source_summary inner))
    | HUn (Not, inner) -> (
        match normalize_source_summary inner with
        | { hexpr = HLitBool true; _ } -> Core_syntax_builders.mk_hbool false
        | { hexpr = HLitBool false; _ } -> Core_syntax_builders.mk_hbool true
        | inner' -> Core_syntax_builders.mk_hnot inner')
    | HBin (And, a, b) -> begin
        match (normalize_source_summary a, normalize_source_summary b) with
        | ({ hexpr = HLitBool false; _ } as x), _ -> x
        | _, ({ hexpr = HLitBool false; _ } as x) -> x
        | { hexpr = HLitBool true; _ }, rhs -> rhs
        | lhs, { hexpr = HLitBool true; _ } -> lhs
        | lhs, rhs -> Core_syntax_builders.mk_hand lhs rhs
      end
    | HBin (Or, a, b) -> begin
        match (normalize_source_summary a, normalize_source_summary b) with
        | ({ hexpr = HLitBool true; _ } as x), _ -> x
        | _, ({ hexpr = HLitBool true; _ } as x) -> x
        | { hexpr = HLitBool false; _ }, rhs -> rhs
        | lhs, { hexpr = HLitBool false; _ } -> lhs
        | lhs, rhs -> Core_syntax_builders.mk_hor lhs rhs
      end
    | HBin (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc f
          (HBin (op, normalize_source_summary a, normalize_source_summary b))
    | HCmp (r, a, b) ->
        Core_syntax_builders.with_hexpr_desc f
          (HCmp (r, normalize_source_summary a, normalize_source_summary b))
  in
  let term_or a b = normalize_source_summary (Core_syntax_builders.mk_hor a b) in
  let term_and a b = normalize_source_summary (Core_syntax_builders.mk_hand a b) in
  let term_not a = normalize_source_summary (Core_syntax_builders.mk_hnot a) in
  let rec phase_summary_obviously_inconsistent (f : Core_syntax.hexpr) : bool =
    match normalize_source_summary f with
    | { hexpr = HLitBool false; _ } -> true
    | { hexpr = HCmp (RNeq, { hexpr = HVar x; _ }, { hexpr = HVar y; _ }); _ }
      when String.equal x y ->
        true
    | { hexpr = HUn (Not, { hexpr = HCmp (REq, { hexpr = HVar x; _ }, { hexpr = HVar y; _ }); _ }); _ }
      when String.equal x y ->
        true
    | { hexpr = HUn (Not, { hexpr = HLitBool true; _ }); _ } -> true
    | { hexpr = HBin (And, a, b); _ } ->
        phase_summary_obviously_inconsistent a || phase_summary_obviously_inconsistent b
    | _ -> false
  in
  let same_product_state (a : product_state_ir) (b : product_state_ir) =
    a.prog_state = b.prog_state
    && a.assume_state_index = b.assume_state_index
    && a.guarantee_state_index = b.guarantee_state_index
  in
  let all_states =
    steps
    |> List.concat_map (fun (step : product_step_ir) -> [ step.src; step.dst ])
    |> List.sort_uniq Stdlib.compare
  in
  let source_summaries =
    all_states
    |> List.filter_map (fun (st : product_state_ir) ->
           let formulas =
             steps
             |> List.filter (fun (step : product_step_ir) ->
                    same_product_state step.src st && step.step_kind = StepSafe)
             |> List.concat_map product_summaries_of_step
             |> List.concat_map guarantee_propagation_requires
             |> List.filter (fun phase_formula -> not (fo_mentions_current_input phase_formula))
             |> List.sort_uniq Stdlib.compare
           in
           let phase_formula =
             match formulas with
             | [] -> None
             | f :: rest ->
                 Some
                   (List.fold_left
                      Core_syntax_builders.mk_hor
                      f rest
                   |> normalize_source_summary)
           in
           match phase_formula with
           | None -> None
           | Some phase_formula ->
               if phase_summary_obviously_inconsistent phase_formula then None
               else
                 Some
                   ({
                     origin = OriginSourceProductSummary;
                     anchor = ClauseAnchorProductState st;
                     hypotheses =
                       [
                         current (FactProgramState st.prog_state);
                         current (FactGuaranteeState st.guarantee_state_index);
                       ];
                     conclusions =
                       [ current (FactPhaseFormula phase_formula); current (FactFormula phase_formula) ];
                   } : generated_clause_ir))
  in
  let raw_summaries = source_summaries in
  let phase_formula_of_clause (clause : generated_clause_ir) =
    clause.conclusions
    |> List.find_map (fun (fact : clause_fact_ir) ->
           match (fact.time, fact.desc) with
           | CurrentTick, FactPhaseFormula fo_formula -> Some fo_formula
           | _ -> None)
  in
  let anchor_state_of_clause (clause : generated_clause_ir) =
    match clause.anchor with
    | ClauseAnchorProductState st -> Some st
    | ClauseAnchorProductStep _ -> None
  in
  let raw_formula_table = Hashtbl.create 16 in
  List.iter
    (fun (clause : generated_clause_ir) ->
      match (anchor_state_of_clause clause, phase_formula_of_clause clause) with
      | Some st, Some phase_formula ->
          let key = (st.prog_state, st.guarantee_state_index) in
          let merged =
            match Hashtbl.find_opt raw_formula_table key with
            | None -> phase_formula
            | Some prev -> term_or prev phase_formula
          in
          Hashtbl.replace raw_formula_table key merged
      | _ -> ())
    raw_summaries;
  let by_prog_state = Hashtbl.create 16 in
  Hashtbl.iter
    (fun ((prog_state, gidx) as key) phase_formula ->
      let prev = Hashtbl.find_opt by_prog_state prog_state |> Option.value ~default:[] in
      Hashtbl.replace by_prog_state prog_state ((gidx, phase_formula, key) :: prev))
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
              | Some covered -> term_and raw_fo (term_not covered)
            in
            Hashtbl.replace exclusive_formula_table key (normalize_source_summary exclusive);
            let covered_opt =
              match covered_opt with
              | None -> Some raw_fo
              | Some covered -> Some (term_or covered raw_fo)
            in
            (covered_opt, ()))
          (None, ()) entries
      in
      ())
    by_prog_state;
  raw_summaries
  |> List.map (fun (clause : generated_clause_ir) ->
         match anchor_state_of_clause clause with
         | None -> clause
         | Some st ->
             let key = (st.prog_state, st.guarantee_state_index) in
             match Hashtbl.find_opt exclusive_formula_table key with
             | Some phase_formula when not (phase_summary_obviously_inconsistent phase_formula) ->
                 {
                   clause with
                   conclusions =
                     [ current (FactPhaseFormula phase_formula); current (FactFormula phase_formula) ];
                 }
             | _ -> clause)

(** [build_generated_clauses] helper value. *)
