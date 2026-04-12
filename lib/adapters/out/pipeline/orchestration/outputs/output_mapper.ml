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

let obligations_map_text ~(raw : string) ~(summary : Obligation_taxonomy.summary) :
    string =
  let taxonomy_text = Obligation_taxonomy.render_summary summary in
  if String.trim raw = "" then "-- OBC obligation taxonomy --\n" ^ taxonomy_text
  else raw ^ "\n\n-- OBC obligation taxonomy --\n" ^ taxonomy_text

let program_automaton_texts (asts : Pipeline_types.ast_stages) : string * string =
  Pipeline_outputs_helpers.program_automaton_texts asts

let build_labels_text ~(program_automaton_text : string)
    ~(artifacts : Pipeline_artifact_bundle.t) : string =
  String.concat "\n\n"
    [
      program_automaton_text;
      artifacts.guarantee_automaton_text;
      artifacts.assume_automaton_text;
      artifacts.product_text;
    ]

let graph_pngs ~(generate_main_png : bool) ~(program_dot : string)
    ~(guarantee_automaton_dot : string) ~(assume_automaton_dot : string)
    ~(product_dot : string) :
    string option
    * string option
    * string option
    * string option
    * string option
    * string option
    * string option
    * string option
    * string option
    * string option =
  let dot_png, dot_png_error =
    if generate_main_png && String.trim product_dot <> "" then
      Graphviz_render.dot_png_from_text_diagnostic product_dot
    else (None, None)
  in
  let program_png, program_png_error =
    if String.trim program_dot = "" then (None, Some "Program automaton DOT is empty.")
    else Graphviz_render.dot_png_from_text_diagnostic program_dot
  in
  let guarantee_automaton_png, guarantee_automaton_png_error =
    if String.trim guarantee_automaton_dot = "" then
      (None, Some "Guarantee automaton DOT is empty.")
    else Graphviz_render.dot_png_from_text_diagnostic guarantee_automaton_dot
  in
  let assume_automaton_png, assume_automaton_png_error =
    if String.trim assume_automaton_dot = "" then
      (None, Some "Assume automaton DOT is empty.")
    else Graphviz_render.dot_png_from_text_diagnostic assume_automaton_dot
  in
  let product_png, product_png_error =
    if String.trim product_dot = "" then (None, Some "Product automaton DOT is empty.")
    else Graphviz_render.dot_png_from_text_diagnostic product_dot
  in
  ( dot_png,
    dot_png_error,
    program_png,
    program_png_error,
    guarantee_automaton_png,
    guarantee_automaton_png_error,
    assume_automaton_png,
    assume_automaton_png_error,
    product_png,
    product_png_error )

let map_outputs ~(cfg : Pipeline_types.config)
    ~(snapshot : Pipeline_types.pipeline_snapshot)
    ~(artifacts : Pipeline_artifact_bundle.t) ~(proof : Proof_runner.run_output)
    ~(obligation_summary : Obligation_taxonomy.summary) : Pipeline_types.outputs =
  let program_dot, program_automaton_text = program_automaton_texts snapshot.asts in
  let labels_text =
    build_labels_text ~program_automaton_text ~artifacts
  in
  let dot_png, dot_png_error, program_png, program_png_error, guarantee_automaton_png,
      guarantee_automaton_png_error, assume_automaton_png, assume_automaton_png_error,
      product_png, product_png_error =
    graph_pngs ~generate_main_png:cfg.generate_dot_png ~program_dot
      ~guarantee_automaton_dot:artifacts.guarantee_automaton_dot
      ~assume_automaton_dot:artifacts.assume_automaton_dot
      ~product_dot:artifacts.product_dot
  in
  {
    Pipeline_types.why_text = proof.why_text;
    vc_text = proof.vc_text;
    smt_text = proof.smt_text;
    dot_text = artifacts.product_dot;
    labels_text;
    program_automaton_text;
    guarantee_automaton_text = artifacts.guarantee_automaton_text;
    assume_automaton_text = artifacts.assume_automaton_text;
    product_text = artifacts.product_text;
    canonical_text = artifacts.canonical_text;
    obligations_map_text =
      obligations_map_text ~raw:artifacts.obligations_map_text_raw
        ~summary:obligation_summary;
    program_dot;
    guarantee_automaton_dot = artifacts.guarantee_automaton_dot;
    assume_automaton_dot = artifacts.assume_automaton_dot;
    product_dot = artifacts.product_dot;
    canonical_dot = artifacts.canonical_dot;
    stage_meta =
      Pipeline_outputs_helpers.stage_meta snapshot.infos
      @ [
          ( "obligations_taxonomy",
            Obligation_taxonomy.to_stage_meta obligation_summary );
        ];
    goals = proof.goals;
    proof_traces = proof.proof_traces;
    vc_locs = proof.vc_locs;
    vc_locs_ordered = proof.vc_locs_ordered;
    vc_spans_ordered =
      List.map
        (fun (span : Pipeline_types.text_span) ->
          (span.start_offset, span.end_offset))
        proof.vc_spans_ordered;
    why_spans = proof.why_spans;
    vc_ids_ordered = proof.vc_ids_ordered;
    why_time_s = 0.0;
    automata_generation_time_s = 0.0;
    automata_build_time_s = 0.0;
    why3_prep_time_s = 0.0;
    dot_png;
    dot_png_error;
    program_png;
    program_png_error;
    guarantee_automaton_png;
    guarantee_automaton_png_error;
    assume_automaton_png;
    assume_automaton_png_error;
    product_png;
    product_png_error;
    historical_clauses_text = "";
    eliminated_clauses_text = "";
  }

let map_automata_outputs ~(generate_png : bool)
    ~(snapshot : Pipeline_types.pipeline_snapshot)
    ~(artifacts : Pipeline_artifact_bundle.t)
    ~(obligation_summary : Obligation_taxonomy.summary) :
    Pipeline_types.automata_outputs =
  let program_dot, program_automaton_text = program_automaton_texts snapshot.asts in
  let labels_text =
    build_labels_text ~program_automaton_text ~artifacts
  in
  let dot_png, dot_png_error, program_png, program_png_error, guarantee_automaton_png,
      guarantee_automaton_png_error, assume_automaton_png, assume_automaton_png_error,
      product_png, product_png_error =
    graph_pngs ~generate_main_png:generate_png ~program_dot
      ~guarantee_automaton_dot:artifacts.guarantee_automaton_dot
      ~assume_automaton_dot:artifacts.assume_automaton_dot
      ~product_dot:artifacts.product_dot
  in
  {
    Pipeline_types.dot_text = artifacts.product_dot;
    labels_text;
    program_automaton_text;
    guarantee_automaton_text = artifacts.guarantee_automaton_text;
    assume_automaton_text = artifacts.assume_automaton_text;
    product_text = artifacts.product_text;
    canonical_text = artifacts.canonical_text;
    obligations_map_text =
      obligations_map_text ~raw:artifacts.obligations_map_text_raw
        ~summary:obligation_summary;
    program_dot;
    guarantee_automaton_dot = artifacts.guarantee_automaton_dot;
    assume_automaton_dot = artifacts.assume_automaton_dot;
    product_dot = artifacts.product_dot;
    canonical_dot = artifacts.canonical_dot;
    dot_png;
    dot_png_error;
    program_png;
    program_png_error;
    guarantee_automaton_png;
    guarantee_automaton_png_error;
    assume_automaton_png;
    assume_automaton_png_error;
    product_png;
    product_png_error;
    stage_meta =
      Pipeline_outputs_helpers.stage_meta snapshot.infos
      @ [
          ( "obligations_taxonomy",
            Obligation_taxonomy.to_stage_meta obligation_summary );
        ];
    historical_clauses_text = "";
    eliminated_clauses_text = "";
  }
