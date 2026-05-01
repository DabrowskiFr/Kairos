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

(** Shared public types for pipeline orchestration, outputs, and diagnostics. *)
open Core_syntax

(** One goal status line: [name, status, time_s, dump_path, vc_id]. *)

type goal_info = string * string * float * string option * string option

(** Half-open span in a generated text artifact ([start_offset, end_offset]). *)

type text_span = {
  start_offset : int;
  end_offset : int;
}

(** Structured diagnostic attached to one proof trace. *)

type proof_diagnostic = {
  category : string;
  summary : string;
  detail : string;
  probable_cause : string option;
  missing_elements : string list;
  goal_symbols : string list;
  analysis_method : string;
  solver_detail : string option;
  native_unsat_core_solver : string option;
  native_unsat_core_hypothesis_ids : int list;
  native_counterexample_solver : string option;
  native_counterexample_model : string option;
  kairos_core_hypotheses : string list;
  why3_noise_hypotheses : string list;
  relevant_hypotheses : string list;
  context_hypotheses : string list;
  unused_hypotheses : string list;
  suggestions : string list;
  limitations : string list;
}

(** Per-goal trace enriched with solver status and artifact locations. *)

type proof_trace = {
  goal_index : int;
  stable_id : string;
  goal_name : string;
  status : string;
  solver_status : string;
  time_s : float;
  source : string;
  node : string option;
  transition : string option;
  obligation_kind : string;
  obligation_family : string option;
  obligation_category : string option;
  vc_id : string option;
  source_span : Loc.loc option;
  why_span : text_span option;
  vc_span : text_span option;
  smt_span : text_span option;
  dump_path : string option;
  diagnostic : proof_diagnostic;
}

(** Main outputs of a complete pipeline run. *)

type outputs = {
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  program_automaton_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  canonical_text : string;
  obligations_map_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  canonical_dot : string;
  flow_meta : (string * (string * string) list) list;
  goals : goal_info list;
  proof_traces : proof_trace list;
  vc_locs : (int * Loc.loc) list;
  vc_locs_ordered : Loc.loc list;
  vc_spans_ordered : (int * int) list;
  why_spans : (int * (int * int)) list;
  vc_ids_ordered : int list;
  why_time_s : float;
  automata_generation_time_s : float;
  automata_build_time_s : float;
  why3_prep_time_s : float;
  dot_png : string option;
  dot_png_error : string option;
  program_png : string option;
  program_png_error : string option;
  guarantee_automaton_png : string option;
  guarantee_automaton_png_error : string option;
  assume_automaton_png : string option;
  assume_automaton_png_error : string option;
  product_png : string option;
  product_png_error : string option;
  historical_clauses_text : string;
  eliminated_clauses_text : string;
}

(** Outputs of the instrumentation/automata dump pass. *)

type automata_outputs = {
  dot_text : string;
  labels_text : string;
  program_automaton_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  canonical_text : string;
  obligations_map_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  canonical_dot : string;
  dot_png : string option;
  dot_png_error : string option;
  program_png : string option;
  program_png_error : string option;
  guarantee_automaton_png : string option;
  guarantee_automaton_png_error : string option;
  assume_automaton_png : string option;
  assume_automaton_png_error : string option;
  product_png : string option;
  product_png_error : string option;
  flow_meta : (string * (string * string) list) list;
  historical_clauses_text : string;
  eliminated_clauses_text : string;
}

(** Why text output with attached flow metadata. *)

type why_outputs = { why_text : string; flow_meta : (string * (string * string) list) list }
(** VC/SMT text outputs. *)

type obligations_outputs = { vc_text : string; smt_text : string }

(** Frontend parsing payload consumed by snapshot builders.

    It bundles parsed source-level data and the internal verification model. *)

type frontend_payload = {
  imports : string list;
  parse_info : Flow_info.parse_info;
  parsed : Ast.program;
  verification_model : Verification_model.program_model;
}

(** Snapshot of program forms produced by early and middle pipeline stages. *)

type ast_flow = {
  imports : string list;
  parsed : Ast.program;
  verification_model : Verification_model.program_model;
  automata_generation : Ast.program;
  automata : (ident * Automaton_types.automata_spec) list;
  summaries : Ir.node_ir list;
  instrumentation : Ir.node_ir list;
}

(** Stage metadata attached to a snapshot. *)

type flow_infos = {
  parse : Flow_info.parse_info option;
  automata_generation : Flow_info.automata_info option;
  summaries : Flow_info.summaries_info option;
  instrumentation : Flow_info.instrumentation_info option;
}

(** Immutable snapshot consumed by output/proof adapters. *)

type pipeline_snapshot = {
  asts : ast_flow;
  infos : flow_infos;
}

(** Runtime configuration of the full pipeline execution. *)

type config = {
  input_file : string;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  collect_traceability : bool;
  compute_proof_diagnostics : bool;
  prove : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_dot_png : bool;
}

(** Unified pipeline error type. *)

type error =
  | Parse_error of string
  | Flow_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

(** Pretty-printer for pipeline errors. *)

val error_to_string : error -> string
