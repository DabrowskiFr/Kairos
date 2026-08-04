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

let is_prove_only_run (cfg : Kr_engine.Pipeline_config.config) : bool =
  cfg.prove && not cfg.wp_only && not cfg.generate_vc_text
  && not cfg.generate_smt_text && not cfg.generate_dot_png
  && not cfg.compute_proof_diagnostics
  && Option.is_none cfg.proof_progress_path

let minimal_outputs_of_proof ~(cfg : Kr_engine.Pipeline_config.config)
    ~(infos : Kr_engine.Flow_info.pipeline_info)
    (proof : Proof_runner.run_output) : Kr_engine.Pipeline_artifacts.outputs =
  {
    Kr_engine.Pipeline_artifacts.why_text = proof.why_text;
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
        ~proof_optimizations:cfg.proof_optimizations infos;
    goals = proof.goals;
    proof_traces = proof.proof_traces;
    vc_locs = proof.vc_locs;
    vc_locs_ordered = proof.vc_locs_ordered;
    vc_spans_ordered =
      List.map
        (fun (span : Kr_engine.Pipeline_proof_types.text_span) ->
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

let build_outputs ~(cfg : Kr_engine.Pipeline_config.config)
    ~(proof_cases : Proof_case_program.t)
    ~(product_nodes : Orchestration.product_node list)
    ~(proof_plans :
       Kr_verification_obligations.Verification_proof_ir.t list)
    ~(infos : Kr_engine.Flow_info.pipeline_info) :
  (Kr_engine.Pipeline_artifacts.outputs, Kr_engine.Pipeline_error.t) result =
  if is_prove_only_run cfg then (
    let t_proof = Unix.gettimeofday () in
    match Proof_runner.run ~cfg ~proof_plans with
    | Error _ as err -> err
    | Ok proof ->
        Runtime_metrics.record_output_proof_run
          ~elapsed_s:(Unix.gettimeofday () -. t_proof);
        let t_map = Unix.gettimeofday () in
        let out = minimal_outputs_of_proof ~cfg ~infos proof in
        Runtime_metrics.record_output_map
          ~elapsed_s:(Unix.gettimeofday () -. t_map);
        Ok out)
  else
    let t_artifacts = Unix.gettimeofday () in
    let artifacts =
      Pipeline_artifact_bundle.build ~product_nodes
    in
    Runtime_metrics.record_output_artifact
      ~elapsed_s:(Unix.gettimeofday () -. t_artifacts);
    let t_proof = Unix.gettimeofday () in
    match Proof_runner.run ~cfg ~proof_plans with
    | Error _ as err -> err
    | Ok proof ->
        Runtime_metrics.record_output_proof_run
          ~elapsed_s:(Unix.gettimeofday () -. t_proof);
        let t_map = Unix.gettimeofday () in
        let out =
          Output_mapper.map_outputs ~cfg ~proof_cases ~infos
            ~artifacts ~proof
        in
        Runtime_metrics.record_output_map
          ~elapsed_s:(Unix.gettimeofday () -. t_map);
        Ok out
