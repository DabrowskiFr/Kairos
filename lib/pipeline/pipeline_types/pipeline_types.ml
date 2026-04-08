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

include struct
  open Ast

  type goal_info = string * string * float * string option * string * string option

  type text_span = {
    start_offset : int;
    end_offset : int;
  }

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
    origin_ids : int list;
    vc_id : string option;
    source_span : Ast.loc option;
    why_span : text_span option;
    vc_span : text_span option;
    smt_span : text_span option;
    dump_path : string option;
    diagnostic : proof_diagnostic;
  }

  type outputs = {
    why_text : string;
    vc_text : string;
    smt_text : string;
    dot_text : string;
    labels_text : string;
    program_automaton_text : string;
    guarantee_automaton_text : string;
    assume_automaton_text : string;
    guarantee_automaton_tex : string;
    assume_automaton_tex : string;
    product_tex : string;
    product_tex_explicit : string;
    canonical_tex : string;
    product_text : string;
    canonical_text : string;
    obligations_map_text : string;
    program_dot : string;
    guarantee_automaton_dot : string;
    assume_automaton_dot : string;
    product_dot : string;
    product_dot_explicit : string;
    canonical_dot : string;
    stage_meta : (string * (string * string) list) list;
    goals : goal_info list;
    proof_traces : proof_trace list;
    vc_sources : (int * string) list;
    task_sequents : (string list * string) list;
    vc_locs : (int * Ast.loc) list;
    vc_locs_ordered : Ast.loc list;
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

  type automata_outputs = {
    dot_text : string;
    labels_text : string;
    program_automaton_text : string;
    guarantee_automaton_text : string;
    assume_automaton_text : string;
    guarantee_automaton_tex : string;
    assume_automaton_tex : string;
    product_tex : string;
    product_tex_explicit : string;
    canonical_tex : string;
    product_text : string;
    canonical_text : string;
    obligations_map_text : string;
    program_dot : string;
    guarantee_automaton_dot : string;
    assume_automaton_dot : string;
    product_dot : string;
    product_dot_explicit : string;
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
    stage_meta : (string * (string * string) list) list;
    historical_clauses_text : string;
    eliminated_clauses_text : string;
  }

  type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }
  type obligations_outputs = { vc_text : string; smt_text : string }

type ast_stages = {
  source : Source_file.t;
  parsed : Ast.program;
  automata_generation : Ast.program;
  automata : Automaton_types.node_builds;
  contracts : Ir.node_ir list;
  instrumentation : Ir.node_ir list;
}

  type stage_infos = {
    parse : Stage_info.parse_info option;
    automata_generation : Stage_info.automata_info option;
    contracts : Stage_info.formulas_info option;
    instrumentation : Stage_info.instrumentation_info option;
  }

  type config = {
    input_file : string;
    prover : string;
    prover_cmd : string option;
    wp_only : bool;
    smoke_tests : bool;
    timeout_s : int;
    selected_goal_index : int option;
    compute_proof_diagnostics : bool;
    prefix_fields : bool;
    prove : bool;
    generate_vc_text : bool;
    generate_smt_text : bool;
    generate_dot_png : bool;
    disable_why3_optimizations : bool;
  }

  type error =
    | Parse_error of string
    | Stage_error of string
    | Why3_error of string
    | Prove_error of string
    | Io_error of string

  let error_to_string = function
    | Parse_error msg -> msg
    | Stage_error msg -> msg
    | Why3_error msg -> msg
    | Prove_error msg -> msg
    | Io_error msg -> msg
end
