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
let get_param_string (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`String s) -> Some s
      | _ -> None)
  | _ -> None

let get_param_bool (params : Yojson.Safe.t) key default =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`Bool b) -> b
      | _ -> default)
  | _ -> default

let get_param_int (params : Yojson.Safe.t) key default =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`Int n) -> n
      | _ -> default)
  | _ -> default

let get_param_obj (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`Assoc ys) -> Some ys
      | _ -> None)
  | _ -> None

let get_param_list (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`List ys) -> Some ys
      | _ -> None)
  | _ -> None

let get_text_document_uri (params : Yojson.Safe.t) =
  match get_param_obj params "textDocument" with
  | Some td -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
  | None -> None

let get_did_open_text (params : Yojson.Safe.t) =
  match get_param_obj params "textDocument" with
  | Some td -> (match List.assoc_opt "text" td with Some (`String s) -> Some s | _ -> None)
  | None -> None

let get_did_change_text (params : Yojson.Safe.t) =
  match get_param_list params "contentChanges" with
  | Some changes ->
      let rec last_text acc = function
        | [] -> acc
        | (`Assoc c) :: tl ->
            let next = match List.assoc_opt "text" c with Some (`String s) -> Some s | _ -> acc in
            last_text next tl
        | _ :: tl -> last_text acc tl
      in
      last_text None changes
  | None -> None

let position_from_params (params : Yojson.Safe.t) : (int * int) option =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt "position" xs with
      | Some (`Assoc p) -> (
          match (List.assoc_opt "line" p, List.assoc_opt "character" p) with
          | Some (`Int l), Some (`Int c) -> Some (l, c)
          | _ -> None)
      | _ -> None)
  | _ -> None

let client_supports_work_done_progress (params : Yojson.Safe.t) : bool =
  match get_param_obj params "capabilities" with
  | Some caps -> (
      match List.assoc_opt "window" caps with
      | Some (`Assoc win) ->
          (match List.assoc_opt "workDoneProgress" win with Some (`Bool b) -> b | _ -> false)
      | _ -> false)
  | None -> false

let loc_of_ast (l : Loc.loc) : Lsp_protocol.loc =
  { line = l.line; col = l.col; line_end = l.line_end; col_end = l.col_end }

let text_span_of_pipeline (span : Pipeline_types.text_span) : Lsp_protocol.text_span =
  { start_offset = span.start_offset; end_offset = span.end_offset }

let proof_diagnostic_of_pipeline (diag : Pipeline_types.proof_diagnostic) : Lsp_protocol.proof_diagnostic =
  {
    category = diag.category;
    summary = diag.summary;
    detail = diag.detail;
    probable_cause = diag.probable_cause;
    missing_elements = diag.missing_elements;
    goal_symbols = diag.goal_symbols;
    analysis_method = diag.analysis_method;
    solver_detail = diag.solver_detail;
    native_unsat_core_solver = diag.native_unsat_core_solver;
    native_unsat_core_hypothesis_ids = diag.native_unsat_core_hypothesis_ids;
    native_counterexample_solver = diag.native_counterexample_solver;
    native_counterexample_model = diag.native_counterexample_model;
    kairos_core_hypotheses = diag.kairos_core_hypotheses;
    why3_noise_hypotheses = diag.why3_noise_hypotheses;
    relevant_hypotheses = diag.relevant_hypotheses;
    context_hypotheses = diag.context_hypotheses;
    unused_hypotheses = diag.unused_hypotheses;
    suggestions = diag.suggestions;
    limitations = diag.limitations;
  }

let proof_trace_of_pipeline (trace : Pipeline_types.proof_trace) : Lsp_protocol.proof_trace =
  {
    goal_index = trace.goal_index;
    stable_id = trace.stable_id;
    goal_name = trace.goal_name;
    status = trace.status;
    solver_status = trace.solver_status;
    time_s = trace.time_s;
    source = trace.source;
    node = trace.node;
    transition = trace.transition;
    obligation_kind = trace.obligation_kind;
    obligation_family = trace.obligation_family;
    obligation_category = trace.obligation_category;
    vc_id = trace.vc_id;
    source_span = Option.map loc_of_ast trace.source_span;
    why_span = Option.map text_span_of_pipeline trace.why_span;
    vc_span = Option.map text_span_of_pipeline trace.vc_span;
    smt_span = Option.map text_span_of_pipeline trace.smt_span;
    dump_path = trace.dump_path;
    diagnostic = proof_diagnostic_of_pipeline trace.diagnostic;
  }

let map_outputs (o : Pipeline_types.outputs) : Lsp_protocol.outputs =
  {
    why_text = o.why_text;
    vc_text = o.vc_text;
    smt_text = o.smt_text;
    dot_text = o.dot_text;
    labels_text = o.labels_text;
    program_automaton_text = o.program_automaton_text;
    guarantee_automaton_text = o.guarantee_automaton_text;
    assume_automaton_text = o.assume_automaton_text;
    product_text = o.product_text;
    canonical_text = o.canonical_text;
    obligations_map_text = o.obligations_map_text;
    program_dot = o.program_dot;
    guarantee_automaton_dot = o.guarantee_automaton_dot;
    assume_automaton_dot = o.assume_automaton_dot;
    product_dot = o.product_dot;
    canonical_dot = o.canonical_dot;
    stage_meta = o.stage_meta;
    goals = o.goals;
    proof_traces = List.map proof_trace_of_pipeline o.proof_traces;
    vc_locs = List.map (fun (i, l) -> (i, loc_of_ast l)) o.vc_locs;
    vc_locs_ordered = List.map loc_of_ast o.vc_locs_ordered;
    vc_spans_ordered = o.vc_spans_ordered;
    why_spans = o.why_spans;
    vc_ids_ordered = o.vc_ids_ordered;
    why_time_s = o.why_time_s;
    automata_generation_time_s = o.automata_generation_time_s;
    automata_build_time_s = o.automata_build_time_s;
    why3_prep_time_s = o.why3_prep_time_s;
    dot_png = o.dot_png;
    dot_png_error = o.dot_png_error;
    program_png = o.program_png;
    program_png_error = o.program_png_error;
    guarantee_automaton_png = o.guarantee_automaton_png;
    guarantee_automaton_png_error = o.guarantee_automaton_png_error;
    assume_automaton_png = o.assume_automaton_png;
    assume_automaton_png_error = o.assume_automaton_png_error;
    product_png = o.product_png;
    product_png_error = o.product_png_error;
    historical_clauses_text = o.historical_clauses_text;
    eliminated_clauses_text = o.eliminated_clauses_text;
  }

let map_automata (o : Pipeline_types.automata_outputs) : Lsp_protocol.automata_outputs =
  {
    dot_text = o.dot_text;
    labels_text = o.labels_text;
    program_automaton_text = o.program_automaton_text;
    guarantee_automaton_text = o.guarantee_automaton_text;
    assume_automaton_text = o.assume_automaton_text;
    product_text = o.product_text;
    canonical_text = o.canonical_text;
    obligations_map_text = o.obligations_map_text;
    program_dot = o.program_dot;
    guarantee_automaton_dot = o.guarantee_automaton_dot;
    assume_automaton_dot = o.assume_automaton_dot;
    product_dot = o.product_dot;
    canonical_dot = o.canonical_dot;
    dot_png = o.dot_png;
    dot_png_error = o.dot_png_error;
    program_png = o.program_png;
    program_png_error = o.program_png_error;
    guarantee_automaton_png = o.guarantee_automaton_png;
    guarantee_automaton_png_error = o.guarantee_automaton_png_error;
    assume_automaton_png = o.assume_automaton_png;
    assume_automaton_png_error = o.assume_automaton_png_error;
    product_png = o.product_png;
    product_png_error = o.product_png_error;
    stage_meta = o.stage_meta;
    historical_clauses_text = o.historical_clauses_text;
    eliminated_clauses_text = o.eliminated_clauses_text;
  }

let map_why (o : Pipeline_types.why_outputs) : Lsp_protocol.why_outputs =
  { why_text = o.why_text; stage_meta = o.stage_meta }

let map_oblig (o : Pipeline_types.obligations_outputs) : Lsp_protocol.obligations_outputs =
  { vc_text = o.vc_text; smt_text = o.smt_text }
