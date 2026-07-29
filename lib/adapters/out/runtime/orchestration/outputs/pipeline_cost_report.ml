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

(** Whole-pipeline cost report composition. *)

open Pipeline_cost_report_common

let flow_meta_json ~proof_optimizations infos =
  Pipeline_outputs_helpers.flow_meta
    ~proof_optimizations infos
  |> json_list (fun (section, fields) ->
         json_assoc
           [
             ("section", json_string section);
             ( "fields",
               json_assoc (List.map (fun (k, v) -> (k, json_string v)) fields) );
           ])

let proof_optimizations_json (opts : Pipeline_config.proof_optimizations) =
  json_assoc
    [
      ( "proof_case_decomposition_strategy",
        json_string
          (Pipeline_config.string_of_proof_case_decomposition_strategy
             opts.verification.proof_case_decomposition_strategy) );
      ( "reachability_strategy",
        json_string
          (Pipeline_config.string_of_reachability_strategy
             opts.verification.reachability_strategy) );
      ( "group_step_contracts",
        json_bool
          (Pipeline_config.groups_step_contracts
             opts.verification.proof_plan_strategy) );
      ( "deduplicate_obligation_conditions",
        json_bool
          (Pipeline_config.deduplicates_obligation_conditions
             opts.verification.proof_plan_strategy) );
      ( "share_contract_formulas",
        json_bool
          (Pipeline_config.shares_contract_formulas
             opts.verification.proof_plan_strategy) );
      ( "bundle_individual_postconditions",
        json_bool
          (Pipeline_config.bundles_individual_postconditions
             opts.verification.proof_plan_strategy) );
    ]

let render_json ~input_file ~why_text_s ~proof_optimizations
    ~infos ~proof_cases ~instrumentation ~why_text =
  let root =
    json_assoc
      [
        ("format", json_string "kairos-cost-report-v1");
        ("input_file", json_string input_file);
        ( "timings",
          json_assoc
            [
              ("why_text_generation_s", json_float why_text_s);
            ] );
        ("proof_optimizations", proof_optimizations_json proof_optimizations);
        ( "flow_meta",
          flow_meta_json ~proof_optimizations infos );
        ("source", Pipeline_cost_report_source.source_json proof_cases);
        ( "formula_population",
          Pipeline_cost_report_facts.formula_population_json
            ~proof_cases ~instrumentation );
        ("why3", Pipeline_cost_report_why3.why3_json why_text ~why_text_s);
        ( "notes",
          json_list json_string
            [
              "This report is observational and does not change proof obligations.";
              "Formula population is measured on source and canonical IR formulas.";
              "Why3 metrics are computed on generated WhyML text before VC/SMT solving.";
            ] );
      ]
  in
  Json.pretty_to_string root ^ "\n"
