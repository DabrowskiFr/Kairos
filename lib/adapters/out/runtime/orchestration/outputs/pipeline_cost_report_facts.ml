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
open Pretty
open Pipeline_cost_report_common
open Pipeline_cost_report_labels
open Pipeline_cost_report_syntax

module PK = Proof_kernel_types

type fact_stat = {
  key : string;
  hash : string;
  size : int;
  max_pre_depth : int;
  arity : int;
  mutable occurrences : int;
  mutable origins : StringSet.t;
  mutable phases : StringSet.t;
}

let new_fact_stat key h ~origin ~phase =
  {
    key;
    hash = Digest.to_hex (Digest.string key);
    size = hexpr_size h;
    max_pre_depth = hexpr_max_pre_depth h;
    arity = StringSet.cardinal (hexpr_free_variables h);
    occurrences = 1;
    origins = StringSet.singleton origin;
    phases = StringSet.singleton phase;
  }

let add_fact table ~origin ~phase h =
  let key = string_of_fo h in
  match Hashtbl.find_opt table key with
  | Some stat ->
      stat.occurrences <- stat.occurrences + 1;
      stat.origins <- StringSet.add origin stat.origins;
      stat.phases <- StringSet.add phase stat.phases
  | None -> Hashtbl.add table key (new_fact_stat key h ~origin ~phase)

let fact_stats table = Hashtbl.fold (fun _ stat acc -> stat :: acc) table []

let fact_repeated_cost stat = stat.size * max 0 (stat.occurrences - 1)

let compare_fact_hotness a b =
  match Int.compare (fact_repeated_cost b) (fact_repeated_cost a) with
  | 0 -> begin
      match Int.compare b.occurrences a.occurrences with
      | 0 -> Int.compare b.size a.size
      | c -> c
    end
  | c -> c

let json_fact_stat stat =
  json_assoc
    [
      ("hash", json_string stat.hash);
      ("size", json_int stat.size);
      ("occurrences", json_int stat.occurrences);
      ("repeated_node_cost", json_int (fact_repeated_cost stat));
      ("arity", json_int stat.arity);
      ("max_pre_depth", json_int stat.max_pre_depth);
      ("origins", json_list json_string (StringSet.elements stat.origins));
      ("phases", json_list json_string (StringSet.elements stat.phases));
      ("formula", json_string (truncate_string 240 stat.key));
    ]

let formula_population_json_of_facts facts =
  let unique_count = List.length facts in
  let total_occurrences = sum_int (List.map (fun f -> f.occurrences) facts) in
  let duplicated_facts = count_if (fun f -> f.occurrences > 1) facts in
  let duplicated_occurrences =
    sum_int (List.map (fun f -> max 0 (f.occurrences - 1)) facts)
  in
  let repeated_node_cost = sum_int (List.map fact_repeated_cost facts) in
  let top =
    facts |> List.sort compare_fact_hotness
    |> fun xs ->
    let rec take n = function
      | _ when n <= 0 -> []
      | [] -> []
      | x :: tl -> x :: take (n - 1) tl
    in
    take 30 xs
  in
  json_assoc
    [
      ("unique_formula_count", json_int unique_count);
      ("formula_occurrences", json_int total_occurrences);
      ("duplicated_formula_count", json_int duplicated_facts);
      ("duplicated_occurrences", json_int duplicated_occurrences);
      ("repeated_node_cost", json_int repeated_node_cost);
      ("max_formula_size", json_int (max_int (List.map (fun f -> f.size) facts)));
      ( "max_formula_fanout",
        json_int (max_int (List.map (fun f -> f.occurrences) facts)) );
      ("max_formula_arity", json_int (max_int (List.map (fun f -> f.arity) facts)));
      ("top_repeated_facts", json_list json_fact_stat top);
    ]

let add_rel_fact_formula table ~origin (fact : PK.relational_clause_fact_ir) =
  let phase = phase_string fact.time in
  match fact.desc with
  | PK.RelFactPhaseFormula h | PK.RelFactFormula h ->
      add_fact table ~origin ~phase h
  | PK.RelFactProgramState _ | PK.RelFactGuaranteeState _ | PK.RelFactFalse -> ()

let collect_summary_facts table (node : Ir.node_ir) =
  let node_name = node.semantics.sem_nname in
  let add_summary_formula origin phase (f : Ir.summary_formula) =
    add_fact table ~origin:(origin_for_node node_name origin) ~phase f.logic
  in
  List.iter
    (fun (summary : Ir.product_step_summary) ->
      List.iter
        (add_summary_formula "canonical.propagation_requires" "previous_tick")
        summary.propagation_requires;
      List.iter (add_summary_formula "canonical.requires" "step_tick_context")
        summary.requires;
      List.iter (add_summary_formula "canonical.ensures" "current_tick")
        summary.ensures;
      List.iter
        (fun (case : Ir.safe_product_case) ->
          add_summary_formula "canonical.safe_case.admissible_guard"
            "step_tick_context" case.admissible_guard)
        summary.safe_cases;
      List.iter
        (fun (case : Ir.unsafe_product_case) ->
          add_summary_formula "canonical.unsafe_case.excluded_guard"
            "step_tick_context" case.excluded_guard)
        summary.unsafe_cases)
    node.summaries;
  List.iter
    (add_summary_formula "canonical.init_invariant_goal" "current_tick")
    node.init_invariant_goals

let collect_kernel_facts table ~node_name (node : PK.node_ir) =
  let origin suffix = origin_for_node node_name suffix in
  List.iter
    (fun (edge : PK.automaton_edge_ir) ->
      add_fact table ~origin:(origin "kernel.assume_automaton.edge_guard")
        ~phase:"step_tick_context" edge.guard)
    node.assume_automaton.edges;
  List.iter
    (fun (edge : PK.automaton_edge_ir) ->
      add_fact table ~origin:(origin "kernel.guarantee_automaton.edge_guard")
        ~phase:"step_tick_context" edge.guard)
    node.guarantee_automaton.edges;
  List.iter
    (fun (step : PK.product_step_ir) ->
      add_fact table ~origin:(origin "kernel.product.program_guard")
        ~phase:"step_tick_context" step.program_guard;
      add_fact table ~origin:(origin "kernel.product.assume_guard")
        ~phase:"step_tick_context" step.assume_edge.guard;
      add_fact table ~origin:(origin "kernel.product.guarantee_guard")
        ~phase:"step_tick_context" step.guarantee_edge.guard)
    node.product_steps;
  List.iter
    (fun (summary : PK.proof_step_summary_ir) ->
      List.iter
        (fun (clause : PK.relational_generated_clause_ir) ->
          let origin =
            origin ("kernel.entry_clause." ^ clause_origin_string clause.origin)
          in
          List.iter (add_rel_fact_formula table ~origin) clause.hypotheses;
          List.iter (add_rel_fact_formula table ~origin) clause.conclusions)
        summary.entry_clauses;
      List.iter
        (fun (clause : PK.relational_generated_clause_ir) ->
          let origin =
            origin ("kernel.post_clause." ^ clause_origin_string clause.origin)
          in
          List.iter (add_rel_fact_formula table ~origin) clause.hypotheses;
          List.iter (add_rel_fact_formula table ~origin) clause.conclusions)
        summary.clauses)
    node.proof_step_summaries

let collect_source_ltl_facts table (node : Verification_model.node_model) =
  let origin suffix = origin_for_node node.node_name suffix in
  let rec go origin phase = function
    | LTrue | LFalse -> ()
    | LAtom (a, _, b) ->
        add_fact table ~origin ~phase a;
        add_fact table ~origin ~phase b
    | LNot a | LX a | LG a -> go origin phase a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        go origin phase a;
        go origin phase b
  in
  List.iter (go (origin "source.assume.atom") "source_ltl") node.assumes;
  List.iter (go (origin "source.guarantee.atom") "source_ltl") node.guarantees;
  List.iter
    (fun (inv : Verification_model.state_invariant) ->
      add_fact table ~origin:(origin "source.state_invariant") ~phase:"source_fo"
        inv.formula)
    node.state_invariants

let collect_all_facts snapshot artifacts =
  let table = Hashtbl.create 4096 in
  List.iter (collect_source_ltl_facts table)
    snapshot.Runtime_snapshot.asts.verification_model;
  List.iter (collect_summary_facts table)
    snapshot.Runtime_snapshot.asts.instrumentation;
  List.iter
    (fun (summary : PK.exported_node_summary_ir) ->
      collect_kernel_facts table ~node_name:summary.signature.node_name
        summary.normalized_ir)
    artifacts.Pipeline_artifact_bundle.exported_node_summaries;
  fact_stats table

let formula_population_json snapshot artifacts =
  collect_all_facts snapshot artifacts |> formula_population_json_of_facts
