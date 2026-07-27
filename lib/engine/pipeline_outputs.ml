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

(** Executes output and proof production for the concrete engine flow. *)
include Pipeline_outputs_helpers

let is_prove_only_run (cfg : Pipeline_config.config) : bool =
  cfg.prove && not cfg.wp_only && not cfg.generate_vc_text
  && not cfg.generate_smt_text && not cfg.generate_dot_png
  && not cfg.compute_proof_diagnostics
  && Option.is_none cfg.proof_progress_path

let proof_instrumentation_of_asts asts =
  asts.Runtime_snapshot.proof_backend_nodes

let minimal_outputs_of_proof ~(snapshot : Runtime_snapshot.pipeline_snapshot)
    (proof : Proof_runner.run_output) : Pipeline_artifacts.outputs =
  {
    Pipeline_artifacts.why_text = proof.why_text;
    vc_text = "";
    smt_text = "";
    dot_text = "";
    labels_text = "";
    program_automaton_text = "";
    guarantee_automaton_text = "";
    assume_automaton_text = "";
    product_text = "";
    program_dot = "";
    guarantee_automaton_dot = "";
    assume_automaton_dot = "";
    product_dot = "";
    flow_meta =
      Pipeline_outputs_helpers.flow_meta
        ~proof_encoding:snapshot.proof_encoding
        ~proof_optimizations:snapshot.proof_optimizations snapshot.infos;
    goals = proof.goals;
    proof_traces = proof.proof_traces;
    vc_locs = proof.vc_locs;
    vc_locs_ordered = proof.vc_locs_ordered;
    vc_spans_ordered =
      List.map
        (fun (span : Pipeline_proof_types.text_span) ->
          (span.start_offset, span.end_offset))
        proof.vc_spans_ordered;
    why_spans = proof.why_spans;
    vc_ids_ordered = proof.vc_ids_ordered;
    why_time_s = 0.0;
    automata_generation_time_s = 0.0;
    automata_build_time_s = 0.0;
    why3_prep_time_s = 0.0;
    dot_png = None;
    dot_png_error = None;
    program_png = None;
    program_png_error = None;
    guarantee_automaton_png = None;
    guarantee_automaton_png_error = None;
    assume_automaton_png = None;
    assume_automaton_png_error = None;
    product_png = None;
    product_png_error = None;
  }

let build_outputs ~(cfg : Pipeline_config.config)
    ~(snapshot : Runtime_snapshot.pipeline_snapshot) :
    (Pipeline_artifacts.outputs, Pipeline_error.t) result =
  let asts = snapshot.asts in
  let proof_instrumentation = proof_instrumentation_of_asts asts in
  if is_prove_only_run cfg then (
    let t_proof = Unix.gettimeofday () in
    match
      Proof_runner.run ~cfg ~instrumentation:proof_instrumentation
        ~step_projections:asts.step_projections
    with
    | Error _ as err -> err
    | Ok proof ->
        Runtime_metrics.record_output_proof_run
          ~elapsed_s:(Unix.gettimeofday () -. t_proof);
        let t_map = Unix.gettimeofday () in
        let out = minimal_outputs_of_proof ~snapshot proof in
        Runtime_metrics.record_output_map
          ~elapsed_s:(Unix.gettimeofday () -. t_map);
        Ok out)
  else
    let t_artifacts = Unix.gettimeofday () in
    let artifacts = Pipeline_artifact_bundle.build ~asts in
    Runtime_metrics.record_output_artifact
      ~elapsed_s:(Unix.gettimeofday () -. t_artifacts);
    let t_proof = Unix.gettimeofday () in
    match
      Proof_runner.run ~cfg ~instrumentation:proof_instrumentation
        ~step_projections:asts.step_projections
    with
    | Error _ as err -> err
    | Ok proof ->
        Runtime_metrics.record_output_proof_run
          ~elapsed_s:(Unix.gettimeofday () -. t_proof);
        let t_map = Unix.gettimeofday () in
        let out = Output_mapper.map_outputs ~cfg ~snapshot ~artifacts ~proof in
        Runtime_metrics.record_output_map
          ~elapsed_s:(Unix.gettimeofday () -. t_map);
        Ok out
