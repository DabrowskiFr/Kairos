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

(** Proof-kernel and canonical-summary sections of the cost report. *)

open Core_syntax
open Pretty
open Pipeline_cost_report_common
open Pipeline_cost_report_labels
open Pipeline_cost_report_syntax

module PK = Proof_kernel_types

let runtime_spec_json (summary : PK.exported_node_summary_ir) =
  let ltl_json ltl =
    json_assoc
      [
        ("size", json_int (ltl_size ltl));
        ("temporal_depth", json_int (ltl_temporal_depth ltl));
        ("pre_depth", json_int (ltl_max_pre_depth ltl));
        ("formula", json_string (truncate_string 360 (string_of_ltl ltl)));
      ]
  in
  json_assoc
    [
      ("assume_count", json_int (List.length summary.assumes));
      ("guarantee_count", json_int (List.length summary.guarantees));
      ("total_assume_size", json_int (sum_int (List.map ltl_size summary.assumes)));
      ("total_guarantee_size", json_int (sum_int (List.map ltl_size summary.guarantees)));
      ("max_guarantee_size", json_int (max_int (List.map ltl_size summary.guarantees)));
      ("assumes", json_list ltl_json summary.assumes);
      ("guarantees", json_list ltl_json summary.guarantees);
    ]

let edge_guard_sizes edges =
  List.map (fun (edge : PK.automaton_edge_ir) -> hexpr_size edge.guard) edges

let automaton_json (automaton : PK.safety_automaton_ir) =
  let guard_sizes = edge_guard_sizes automaton.edges in
  json_assoc
    [
      ("state_count", json_int (List.length automaton.state_labels));
      ("edge_count", json_int (List.length automaton.edges));
      ("bad_state_index", json_opt json_int automaton.bad_state_index);
      ("total_guard_size", json_int (sum_int guard_sizes));
      ("max_guard_size", json_int (max_int guard_sizes));
      ("avg_guard_size", json_float (average_int guard_sizes));
    ]

let count_steps_by_kind steps =
  let safe =
    count_if (fun (step : PK.product_step_ir) -> step.step_kind = StepSafe) steps
  in
  let bad_assumption =
    count_if
      (fun (step : PK.product_step_ir) -> step.step_kind = StepBadAssumption)
      steps
  in
  let bad_guarantee =
    count_if
      (fun (step : PK.product_step_ir) -> step.step_kind = StepBadGuarantee)
      steps
  in
  (safe, bad_assumption, bad_guarantee)

let top_counts limit counts =
  counts |> StringMap.bindings
  |> List.sort (fun (_, a) (_, b) -> Int.compare b a)
  |> fun xs ->
  let rec take n = function
    | _ when n <= 0 -> []
    | [] -> []
    | x :: tl -> x :: take (n - 1) tl
  in
  take limit xs

let increment key map =
  let current = Option.value (StringMap.find_opt key map) ~default:0 in
  StringMap.add key (current + 1) map

let product_json (node : PK.node_ir) =
  let steps = node.product_steps in
  let safe, bad_assumption, bad_guarantee = count_steps_by_kind steps in
  let guard_sizes =
    steps
    |> List.map (fun (step : PK.product_step_ir) ->
           hexpr_size step.program_guard + hexpr_size step.assume_edge.guard
           + hexpr_size step.guarantee_edge.guard)
  in
  let by_source =
    List.fold_left
      (fun acc (step : PK.product_step_ir) -> increment (string_of_product_state step.src) acc)
      StringMap.empty steps
  in
  json_assoc
    [
      ("state_count", json_int (List.length node.product_states));
      ("step_count", json_int (List.length steps));
      ("safe_step_count", json_int safe);
      ("bad_assumption_step_count", json_int bad_assumption);
      ("bad_guarantee_step_count", json_int bad_guarantee);
      ("total_step_guard_size", json_int (sum_int guard_sizes));
      ("max_step_guard_size", json_int (max_int guard_sizes));
      ( "top_sources_by_outgoing_steps",
        json_list
          (fun (src, count) ->
            json_assoc [ ("source", json_string src); ("count", json_int count) ])
          (top_counts 20 by_source) );
    ]

let clause_fact_count (clause : PK.relational_generated_clause_ir) =
  List.length clause.hypotheses + List.length clause.conclusions

let clause_formula_count (clause : PK.relational_generated_clause_ir) =
  let is_formula (fact : PK.relational_clause_fact_ir) =
    match fact.desc with
    | PK.RelFactPhaseFormula _ | PK.RelFactFormula _ -> true
    | PK.RelFactProgramState _ | PK.RelFactGuaranteeState _ | PK.RelFactFalse -> false
  in
  count_if is_formula clause.hypotheses + count_if is_formula clause.conclusions

let clause_json name clauses =
  let fact_counts = List.map clause_fact_count clauses in
  let formula_counts = List.map clause_formula_count clauses in
  let by_origin =
    List.fold_left
      (fun acc (clause : PK.relational_generated_clause_ir) ->
        increment (clause_family_string clause.family) acc)
      StringMap.empty clauses
  in
  json_assoc
    [
      ("name", json_string name);
      ("clause_count", json_int (List.length clauses));
      ("total_fact_count", json_int (sum_int fact_counts));
      ("max_fact_count", json_int (max_int fact_counts));
      ("total_formula_fact_count", json_int (sum_int formula_counts));
      ( "by_origin",
        json_list
          (fun (origin, count) ->
            json_assoc [ ("origin", json_string origin); ("count", json_int count) ])
          (StringMap.bindings by_origin) );
    ]

let proof_kernel_json (node : PK.node_ir) =
  let entry_clauses =
    List.concat (List.map (fun (s : PK.proof_step_summary_ir) -> s.entry_clauses) node.proof_step_summaries)
  in
  let post_clauses =
    List.concat (List.map (fun (s : PK.proof_step_summary_ir) -> s.clauses) node.proof_step_summaries)
  in
  json_assoc
    [
      ("summary_count", json_int (List.length node.proof_step_summaries));
      ("symbolic_clause_count", json_int (List.length node.symbolic_generated_clauses));
      ("historical_clause_count", json_int (List.length node.historical_generated_clauses));
      ("eliminated_clause_count", json_int (List.length node.eliminated_generated_clauses));
      ("entry_clauses", clause_json "entry" entry_clauses);
      ("post_clauses", clause_json "post" post_clauses);
    ]

let find_ir_node name nodes =
  List.find_opt (fun (node : Ir.node_ir) -> node.semantics.sem_nname = name) nodes

let canonical_summary_json (summary : Ir.product_step_summary) =
  let formula_sizes formulas =
    List.map (fun (f : Ir.summary_formula) -> hexpr_size f.logic) formulas
  in
  let all_summary_formulas =
    summary.propagation_requires @ summary.requires @ summary.ensures
    @ summary.elaboration_checks
  in
  let sizes = formula_sizes all_summary_formulas in
  json_assoc
    [
      ("safe_case_count", json_int (List.length summary.safe_cases));
      ("unsafe_case_count", json_int (List.length summary.unsafe_cases));
      ("propagation_requires_count", json_int (List.length summary.propagation_requires));
      ("requires_count", json_int (List.length summary.requires));
      ("ensures_count", json_int (List.length summary.ensures));
      ("elaboration_checks_count", json_int (List.length summary.elaboration_checks));
      ("total_summary_formula_size", json_int (sum_int sizes));
      ("max_summary_formula_size", json_int (max_int sizes));
    ]

let canonical_summaries_json (node : Ir.node_ir option) =
  match node with
  | None -> json_assoc [ ("available", json_bool false) ]
  | Some node ->
      let summaries = node.summaries in
      let safe_cases =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.safe_cases) summaries)
      in
      let unsafe_cases =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.unsafe_cases) summaries)
      in
      let propagation_requires =
        sum_int
          (List.map
             (fun (s : Ir.product_step_summary) -> List.length s.propagation_requires)
             summaries)
      in
      let requires =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.requires) summaries)
      in
      let ensures =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.ensures) summaries)
      in
      let elaboration_checks =
        sum_int
          (List.map
             (fun (s : Ir.product_step_summary) ->
               List.length s.elaboration_checks)
             summaries)
      in
      let summary_jsons = List.map canonical_summary_json summaries in
      json_assoc
        [
          ("available", json_bool true);
          ("summary_count", json_int (List.length summaries));
          ("safe_case_count", json_int safe_cases);
          ("unsafe_case_count", json_int unsafe_cases);
          ("propagation_requires_count", json_int propagation_requires);
          ("requires_count", json_int requires);
          ("ensures_count", json_int ensures);
          ("elaboration_checks_count", json_int elaboration_checks);
          ("summaries", `List summary_jsons);
        ]

let source_node_of_runtime_name runtime_name source_nodes =
  let is_runtime_split source_name =
    runtime_name = source_name
    || starts_with ~prefix:(source_name ^ "__kairos_") runtime_name
  in
  List.find_opt
    (fun (n : Verification_model.node_model) -> is_runtime_split n.node_name)
    source_nodes

let node_report_json snapshot (summary : PK.exported_node_summary_ir) =
  let node = summary.normalized_ir in
  let canonical_node =
    find_ir_node summary.signature.node_name snapshot.Runtime_snapshot.asts.instrumentation
  in
  let source_node =
    source_node_of_runtime_name summary.signature.node_name
      snapshot.Runtime_snapshot.asts.verification_model
  in
  json_assoc
    [
      ("name", json_string summary.signature.node_name);
      ("runtime_spec", runtime_spec_json summary);
      ("assume_automaton", automaton_json node.assume_automaton);
      ("guarantee_automaton", automaton_json node.guarantee_automaton);
      ("product", product_json node);
      ("canonical_summaries", canonical_summaries_json canonical_node);
      ("proof_kernel", proof_kernel_json node);
      ( "source",
        match source_node with
        | None -> json_assoc [ ("available", json_bool false) ]
        | Some node -> Pipeline_cost_report_source.source_node_json node );
    ]
