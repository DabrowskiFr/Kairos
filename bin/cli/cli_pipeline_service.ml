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

open Cli_types

module Engine = Kairos_engine.Api
module Pipeline = Engine.Types

let proof_optimizations_of_args args =
  let base =
    if args.no_proof_optimizations then
      Pipeline.reference_proof_optimizations
    else Pipeline.default_proof_optimizations
  in
  {
    Pipeline.group_public_non_w_guarantees =
      base.group_public_non_w_guarantees && not args.no_proof_grouping;
    share_why3_facts = base.share_why3_facts && not args.no_why3_fact_sharing;
    simplify_why3_formulas =
      base.simplify_why3_formulas && not args.no_why3_fo_simplification;
    slice_why3_transition_bodies =
      base.slice_why3_transition_bodies && not args.no_why3_body_slicing;
    simplify_why3_runtime_actions =
      base.simplify_why3_runtime_actions && not args.no_why3_action_simplification;
    deduplicate_why3_terms =
      base.deduplicate_why3_terms && not args.no_why3_term_dedup;
    group_why3_product_steps =
      base.group_why3_product_steps && not args.no_why3_product_step_grouping;
    why3_product_step_group_max_cost =
      Option.value args.why3_product_step_group_max_cost
        ~default:base.why3_product_step_group_max_cost;
  }

  type goal_info = string * string * float * string option * string option
  type flow_meta = (string * (string * string) list) list

  type automata_dump_data = {
    guarantee_automaton_text : string;
    assume_automaton_text : string;
    guarantee_automaton_dot : string;
    assume_automaton_dot : string;
    product_text : string;
    product_dot : string;
    canonical_text : string;
    canonical_dot : string;
    obligations_map_text : string;
  }

  type obligations_dump_data = {
    vc_text : string;
    smt_text : string;
  }

  type run_dump_data = {
    why_text : string;
    vc_text : string;
    smt_text : string;
    flow_meta : flow_meta;
    goals : goal_info list;
    proof_traces : Pipeline.proof_trace list;
  }

  type frontend_check_data = {
    node_count : int;
    assume_count : int;
    guarantee_count : int;
  }

  type c_generation_data = Engine.generated_file list

  let instrumentation_pass = Engine.instrumentation_pass
  let why_pass = Engine.why_pass_with_options
  let obligations_pass = Engine.obligations_pass_with_options
  let cost_report = Engine.cost_report

  let automata_dump_data ~input_file =
    match instrumentation_pass ~generate_png:false ~input_file with
    | Error _ as e -> e
    | Ok out ->
        Ok
          {
            guarantee_automaton_text = out.guarantee_automaton_text;
            assume_automaton_text = out.assume_automaton_text;
            guarantee_automaton_dot = out.guarantee_automaton_dot;
            assume_automaton_dot = out.assume_automaton_dot;
            product_text = out.product_text;
            product_dot = out.product_dot;
            canonical_text = out.canonical_text;
            canonical_dot = out.canonical_dot;
            obligations_map_text = out.obligations_map_text;
          }

  let why_text_dump ~input_file ~proof_encoding ~proof_optimizations =
    match why_pass ~proof_encoding ~proof_optimizations ~input_file with
    | Error _ as e -> e
    | Ok out -> Ok out.why_text

  let obligations_dump_data ~input_file ~proof_encoding ~proof_optimizations =
    match obligations_pass ~proof_encoding ~proof_optimizations ~input_file with
    | Error _ as e -> e
    | Ok out -> Ok { vc_text = out.vc_text; smt_text = out.smt_text }

  let cost_report_dump ~input_file ~proof_encoding ~proof_optimizations =
    match cost_report ~proof_encoding ~proof_optimizations ~input_file with
    | Error _ as e -> e
    | Ok out -> Ok out.cost_report_json

  let normalized_program = Engine.normalized_program_with_options
  let ir_pretty_dump = Engine.ir_pretty_dump_with_options
  let run = Engine.run
  let surface_dump = Engine.surface_dump
  let elaborated_dump = Engine.elaborated_dump

  let frontend_check ~input_file =
    match Engine.frontend_summary ~input_file with
    | Error _ as e -> e
    | Ok summary ->
        Ok
          {
            node_count = summary.node_count;
            assume_count = summary.assume_count;
            guarantee_count = summary.guarantee_count;
          }

  let c_generation = Engine.generate_c

  let run_dump_data ~input_file ~timeout_s ~prove ~generate_why_text
      ~generate_vc_text ~generate_smt_text ~dump_failed_smt ~proof_progress_path
      ~collect_ir_metrics ~stop_on_first_nonvalid ~proof_jobs ~proof_encoding
      ~proof_optimizations =
    let cfg =
      Engine.make_config ~input_file ~wp_only:false ~smoke_tests:false
        ~timeout_s ~compute_proof_diagnostics:false ~prove ~proof_jobs
        ~dump_failed_smt ~collect_ir_metrics ?proof_progress_path
        ~stop_on_first_nonvalid ~proof_encoding ~proof_optimizations
        ~generate_vc_text ~generate_smt_text ~generate_dot_png:false ()
    in
    match run cfg with
    | Error _ as e -> e
    | Ok out ->
        Ok
          {
            why_text = out.why_text;
            vc_text = out.vc_text;
            smt_text = out.smt_text;
            flow_meta = out.flow_meta;
            goals = out.goals;
            proof_traces = out.proof_traces;
          }
