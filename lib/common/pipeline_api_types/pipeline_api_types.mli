(** Shared public types used across pipeline-adjacent libraries. *)

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
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
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
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
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
  automata : Automata_generation.node_builds;
  contracts : Normalized_program.node list;
  instrumentation : Normalized_program.node list;
  imported_summaries : Proof_kernel_ir.exported_node_summary_ir list;
}

type stage_infos = {
  parse : Stage_info.parse_info option;
  automata_generation : Stage_info.automata_info option;
  contracts : Stage_info.contracts_info option;
  instrumentation : Stage_info.instrumentation_info option;
}

type why_translation_mode =
  | Why_mode_no_automata
  | Why_mode_monitor

val string_of_why_translation_mode : why_translation_mode -> string
val why_translation_mode_of_string : string -> why_translation_mode option

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
  why_translation_mode : why_translation_mode;
  prove : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_monitor_text : bool;
  generate_dot_png : bool;
}

type error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

val error_to_string : error -> string
