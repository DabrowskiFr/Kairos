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

let flow_meta_json snapshot =
  Pipeline_outputs_helpers.flow_meta
    ~proof_encoding:snapshot.Runtime_snapshot.proof_encoding
    ~proof_optimizations:snapshot.Runtime_snapshot.proof_optimizations
    snapshot.Runtime_snapshot.infos
  |> json_list (fun (section, fields) ->
         json_assoc
           [
             ("section", json_string section);
             ( "fields",
               json_assoc (List.map (fun (k, v) -> (k, json_string v)) fields) );
           ])

let proof_optimizations_json (opts : Pipeline_types.proof_optimizations) =
  json_assoc
    [
      ("group_public_non_w_guarantees", json_bool opts.group_public_non_w_guarantees);
      ("group_why3_product_steps", json_bool opts.group_why3_product_steps);
    ]

let proof_encoding_json (encoding : Pipeline_types.proof_encoding) =
  json_string (Pipeline_types.string_of_proof_encoding encoding)

let render_json ~input_file ~artifact_build_s ~why_text_s ~snapshot ~artifacts ~why_text =
  let nodes =
    List.map (Pipeline_cost_report_kernel.node_report_json snapshot) artifacts.Pipeline_artifact_bundle.exported_node_summaries
  in
  let root =
    json_assoc
      [
        ("format", json_string "kairos-cost-report-v1");
        ("input_file", json_string input_file);
        ("proof_encoding", proof_encoding_json snapshot.proof_encoding);
        ( "timings",
          json_assoc
            [
              ("artifact_build_s", json_float artifact_build_s);
              ("why_text_generation_s", json_float why_text_s);
            ] );
        ("proof_optimizations", proof_optimizations_json snapshot.proof_optimizations);
        ("flow_meta", flow_meta_json snapshot);
        ("source", Pipeline_cost_report_source.source_json snapshot);
        ("nodes", `List nodes);
        ( "formula_population",
          Pipeline_cost_report_facts.formula_population_json snapshot artifacts );
        ( "transition_lemma_candidates",
          Pipeline_cost_report_transition_lemmas.json artifacts );
        ("why3", Pipeline_cost_report_why3.why3_json why_text ~why_text_s);
        ( "notes",
          json_list json_string
            [
              "This report is observational and does not change proof obligations.";
              "Formula hashes are based on the current pretty-printed FO syntax.";
              "Why3 metrics are computed on generated WhyML text before VC/SMT solving.";
            ] );
      ]
  in
  Json.pretty_to_string root ^ "\n"
