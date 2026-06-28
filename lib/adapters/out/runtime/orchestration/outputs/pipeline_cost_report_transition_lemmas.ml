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

open Pretty
open Pipeline_cost_report_common
open Pipeline_cost_report_labels
open Pipeline_cost_report_syntax

module PK = Proof_kernel_types

type transition_lemma_fact_stat = {
  lemma_fact_key : string;
  lemma_fact_hash : string;
  lemma_fact_size : int;
  lemma_fact_max_pre_depth : int;
  lemma_fact_arity : int;
  mutable lemma_fact_occurrences : int;
  mutable lemma_fact_origins : StringSet.t;
  mutable lemma_fact_phases : StringSet.t;
  mutable lemma_fact_contexts : StringSet.t;
  mutable lemma_fact_runtime_nodes : StringSet.t;
}

type transition_lemma_stat = {
  transition_key : string;
  transition_id : string;
  program_src : string;
  program_dst : string;
  mutable transition_clause_count : int;
  mutable transition_formula_conclusion_count : int;
  mutable transition_structural_conclusion_count : int;
  mutable transition_false_conclusion_count : int;
  mutable transition_contexts : StringSet.t;
  mutable transition_runtime_nodes : StringSet.t;
  mutable transition_step_kinds : StringSet.t;
  mutable transition_origins : StringSet.t;
  mutable transition_phases : StringSet.t;
  transition_facts : (string, transition_lemma_fact_stat) Hashtbl.t;
}

let new_transition_lemma_fact_stat key formula ~origin ~phase ~context ~runtime_node =
  {
    lemma_fact_key = key;
    lemma_fact_hash = Digest.to_hex (Digest.string key);
    lemma_fact_size = hexpr_size formula;
    lemma_fact_max_pre_depth = hexpr_max_pre_depth formula;
    lemma_fact_arity = StringSet.cardinal (hexpr_free_variables formula);
    lemma_fact_occurrences = 1;
    lemma_fact_origins = StringSet.singleton origin;
    lemma_fact_phases = StringSet.singleton phase;
    lemma_fact_contexts = StringSet.singleton context;
    lemma_fact_runtime_nodes = StringSet.singleton runtime_node;
  }

let transition_lemma_fact_repeated_cost fact =
  fact.lemma_fact_size * max 0 (fact.lemma_fact_occurrences - 1)

let transition_lemma_fact_total_cost fact =
  fact.lemma_fact_size * fact.lemma_fact_occurrences

let add_transition_lemma_fact table ~origin ~phase ~context ~runtime_node formula =
  let key = string_of_fo formula in
  match Hashtbl.find_opt table key with
  | Some fact ->
      fact.lemma_fact_occurrences <- fact.lemma_fact_occurrences + 1;
      fact.lemma_fact_origins <- StringSet.add origin fact.lemma_fact_origins;
      fact.lemma_fact_phases <- StringSet.add phase fact.lemma_fact_phases;
      fact.lemma_fact_contexts <- StringSet.add context fact.lemma_fact_contexts;
      fact.lemma_fact_runtime_nodes <- StringSet.add runtime_node fact.lemma_fact_runtime_nodes
  | None ->
      Hashtbl.add table key
        (new_transition_lemma_fact_stat key formula ~origin ~phase ~context
           ~runtime_node)

let compare_transition_lemma_fact_hotness a b =
  match
    Int.compare
      (transition_lemma_fact_repeated_cost b)
      (transition_lemma_fact_repeated_cost a)
  with
  | 0 -> begin
      match Int.compare b.lemma_fact_occurrences a.lemma_fact_occurrences with
      | 0 -> Int.compare b.lemma_fact_size a.lemma_fact_size
      | c -> c
    end
  | c -> c

let transition_lemma_facts stat =
  Hashtbl.fold (fun _ fact acc -> fact :: acc) stat.transition_facts []

let transition_lemma_repeated_cost stat =
  stat |> transition_lemma_facts
  |> List.map transition_lemma_fact_repeated_cost |> sum_int

let transition_lemma_total_cost stat =
  stat |> transition_lemma_facts
  |> List.map transition_lemma_fact_total_cost |> sum_int

let compare_transition_lemma_hotness a b =
  match Int.compare (transition_lemma_repeated_cost b) (transition_lemma_repeated_cost a) with
  | 0 -> begin
      match
        Int.compare b.transition_formula_conclusion_count
          a.transition_formula_conclusion_count
      with
      | 0 -> String.compare a.transition_key b.transition_key
      | c -> c
    end
  | c -> c

let new_transition_lemma_stat (step : PK.product_step_ir) =
  let program_src, program_dst = step.program_transition in
  let transition_key =
    Printf.sprintf "%s|%s|%s" step.program_transition_id program_src program_dst
  in
  {
    transition_key;
    transition_id = step.program_transition_id;
    program_src;
    program_dst;
    transition_clause_count = 0;
    transition_formula_conclusion_count = 0;
    transition_structural_conclusion_count = 0;
    transition_false_conclusion_count = 0;
    transition_contexts = StringSet.empty;
    transition_runtime_nodes = StringSet.empty;
    transition_step_kinds = StringSet.empty;
    transition_origins = StringSet.empty;
    transition_phases = StringSet.empty;
    transition_facts = Hashtbl.create 64;
  }

let transition_lemma_stat table (step : PK.product_step_ir) =
  let program_src, program_dst = step.program_transition in
  let key =
    Printf.sprintf "%s|%s|%s" step.program_transition_id program_src program_dst
  in
  match Hashtbl.find_opt table key with
  | Some stat -> stat
  | None ->
      let stat = new_transition_lemma_stat step in
      Hashtbl.add table key stat;
      stat

let transition_context ~node_name (step : PK.product_step_ir) ~origin ~phase =
  Printf.sprintf "%s;%s;%s;%s->%s;%s->%s;%s;%s" node_name
    (step_kind_string step.step_kind) step.program_transition_id
    step.src.prog_state step.dst.prog_state
    (string_of_product_state step.src) (string_of_product_state step.dst)
    origin phase

let transition_formula_of_rel_fact (fact : PK.relational_clause_fact_ir) =
  match fact.desc with
  | PK.RelFactPhaseFormula formula | PK.RelFactFormula formula -> Some formula
  | PK.RelFactProgramState _ | PK.RelFactGuaranteeState _ | PK.RelFactFalse -> None

let collect_transition_lemma_candidates_for_clause table ~node_name
    (clause : PK.relational_generated_clause_ir) =
  match clause.anchor with
  | Kernel_clause_projection.ClauseProductState _ -> ()
  | Kernel_clause_projection.ClauseProductStep kernel_step ->
      let step = Proof_kernel_clause_context.product_step_of_kernel kernel_step in
      let stat = transition_lemma_stat table step in
      let origin = clause_family_string clause.family in
      stat.transition_clause_count <- stat.transition_clause_count + 1;
      stat.transition_runtime_nodes <- StringSet.add node_name stat.transition_runtime_nodes;
      stat.transition_step_kinds <-
        StringSet.add (step_kind_string step.step_kind) stat.transition_step_kinds;
      stat.transition_origins <- StringSet.add origin stat.transition_origins;
      List.iter
        (fun (fact : PK.relational_clause_fact_ir) ->
          let phase = phase_string fact.time in
          let context = transition_context ~node_name step ~origin ~phase in
          stat.transition_contexts <- StringSet.add context stat.transition_contexts;
          stat.transition_phases <- StringSet.add phase stat.transition_phases;
          match transition_formula_of_rel_fact fact with
          | Some formula ->
              stat.transition_formula_conclusion_count <-
                stat.transition_formula_conclusion_count + 1;
              add_transition_lemma_fact stat.transition_facts ~origin ~phase
                ~context ~runtime_node:node_name formula
          | None -> begin
              match fact.desc with
              | PK.RelFactFalse ->
                  stat.transition_false_conclusion_count <-
                    stat.transition_false_conclusion_count + 1
              | PK.RelFactProgramState _ | PK.RelFactGuaranteeState _ ->
                  stat.transition_structural_conclusion_count <-
                    stat.transition_structural_conclusion_count + 1
              | PK.RelFactPhaseFormula _ | PK.RelFactFormula _ -> ()
            end)
        clause.conclusions

let collect_transition_lemma_candidates artifacts =
  let table = Hashtbl.create 128 in
  List.iter
    (fun (summary : PK.exported_node_summary_ir) ->
      let node_name = summary.signature.node_name in
      List.iter
        (fun (step_summary : PK.proof_step_summary_ir) ->
          List.iter
            (collect_transition_lemma_candidates_for_clause table ~node_name)
            step_summary.clauses)
        summary.normalized_ir.proof_step_summaries)
    artifacts.Pipeline_artifact_bundle.exported_node_summaries;
  Hashtbl.fold (fun _ stat acc -> stat :: acc) table []

let json_transition_lemma_fact fact =
  json_assoc
    [
      ("hash", json_string fact.lemma_fact_hash);
      ("size", json_int fact.lemma_fact_size);
      ("occurrences", json_int fact.lemma_fact_occurrences);
      ("repeated_node_cost", json_int (transition_lemma_fact_repeated_cost fact));
      ("total_node_cost", json_int (transition_lemma_fact_total_cost fact));
      ("arity", json_int fact.lemma_fact_arity);
      ("max_pre_depth", json_int fact.lemma_fact_max_pre_depth);
      ("origin_count", json_int (StringSet.cardinal fact.lemma_fact_origins));
      ("phase_count", json_int (StringSet.cardinal fact.lemma_fact_phases));
      ("context_count", json_int (StringSet.cardinal fact.lemma_fact_contexts));
      ("runtime_node_count", json_int (StringSet.cardinal fact.lemma_fact_runtime_nodes));
      ("origins", json_list json_string (StringSet.elements fact.lemma_fact_origins));
      ("phases", json_list json_string (StringSet.elements fact.lemma_fact_phases));
      ( "sample_contexts",
        json_list json_string
          (fact.lemma_fact_contexts |> StringSet.elements |> top_string_values 5) );
      ("formula", json_string (truncate_string 260 fact.lemma_fact_key));
    ]

let json_transition_lemma_stat stat =
  let facts = transition_lemma_facts stat in
  let duplicated_fact_count = count_if (fun f -> f.lemma_fact_occurrences > 1) facts in
  let top_facts =
    facts |> List.sort compare_transition_lemma_fact_hotness |> top_values 12
  in
  json_assoc
    [
      ("transition_id", json_string stat.transition_id);
      ( "program_transition",
        json_string (Printf.sprintf "%s -> %s" stat.program_src stat.program_dst) );
      ("clause_count", json_int stat.transition_clause_count);
      ( "formula_conclusion_occurrence_count",
        json_int stat.transition_formula_conclusion_count );
      ("unique_formula_count", json_int (List.length facts));
      ("duplicated_formula_count", json_int duplicated_fact_count);
      ("repeated_node_cost", json_int (transition_lemma_repeated_cost stat));
      ("total_node_cost", json_int (transition_lemma_total_cost stat));
      ( "structural_conclusion_count",
        json_int stat.transition_structural_conclusion_count );
      ("false_conclusion_count", json_int stat.transition_false_conclusion_count);
      ("context_count", json_int (StringSet.cardinal stat.transition_contexts));
      ("runtime_node_count", json_int (StringSet.cardinal stat.transition_runtime_nodes));
      ("step_kinds", json_list json_string (StringSet.elements stat.transition_step_kinds));
      ("origins", json_list json_string (StringSet.elements stat.transition_origins));
      ("phases", json_list json_string (StringSet.elements stat.transition_phases));
      ( "sample_contexts",
        json_list json_string
          (stat.transition_contexts |> StringSet.elements |> top_string_values 8) );
      ("top_facts", json_list json_transition_lemma_fact top_facts);
    ]

let json artifacts =
  let candidates = collect_transition_lemma_candidates artifacts in
  let unique_fact_count =
    sum_int
      (List.map
         (fun stat -> List.length (transition_lemma_facts stat))
         candidates)
  in
  let formula_occurrences =
    sum_int
      (List.map
         (fun stat -> stat.transition_formula_conclusion_count)
         candidates)
  in
  let duplicated_fact_count =
    sum_int
      (List.map
         (fun stat ->
           count_if
             (fun fact -> fact.lemma_fact_occurrences > 1)
             (transition_lemma_facts stat))
         candidates)
  in
  let repeated_node_cost =
    sum_int (List.map transition_lemma_repeated_cost candidates)
  in
  let total_node_cost =
    sum_int (List.map transition_lemma_total_cost candidates)
  in
  let top_transitions =
    candidates |> List.sort compare_transition_lemma_hotness |> top_values 20
  in
  json_assoc
    [
      ("transition_count", json_int (List.length candidates));
      ("formula_conclusion_occurrence_count", json_int formula_occurrences);
      ("unique_transition_formula_count", json_int unique_fact_count);
      ("duplicated_transition_formula_count", json_int duplicated_fact_count);
      ("repeated_node_cost", json_int repeated_node_cost);
      ("total_node_cost", json_int total_node_cost);
      ( "structural_conclusion_count",
        json_int
          (sum_int
             (List.map
                (fun stat -> stat.transition_structural_conclusion_count)
                candidates)) );
      ( "false_conclusion_count",
        json_int
          (sum_int
             (List.map
                (fun stat -> stat.transition_false_conclusion_count)
                candidates)) );
      ("top_transitions", json_list json_transition_lemma_stat top_transitions);
    ]
