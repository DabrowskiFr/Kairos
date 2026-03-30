(** JSON payloads exchanged by the Kairos LSP server and clients. *)

type loc = { line : int; col : int; line_end : int; col_end : int }

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
  source_span : loc option;
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
  vc_locs : (int * loc) list;
  vc_locs_ordered : loc list;
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

type rpc_request_id =
  | Rpc_int_id of int
  | Rpc_string_id of string

type goals_ready_payload = { names : string list; vc_ids : int list }

type goal_done_payload = {
  idx : int;
  goal : string;
  status : string;
  time_s : float;
  dump_path : string option;
  source : string;
  vcid : string option;
}

type outputs_ready_notification = { request_id : rpc_request_id; payload : outputs }
type goals_ready_notification = { request_id : rpc_request_id; payload : goals_ready_payload }
type goal_done_notification = { request_id : rpc_request_id; payload : goal_done_payload }

type outline_sections = {
  nodes : (string * int) list;
  transitions : (string * int) list;
  contracts : (string * int) list;
}

type outline_payload = {
  source : outline_sections;
  abstract_program : outline_sections;
}

type goal_tree_entry = {
  idx : int;
  display_no : int;
  goal : string;
  status : string;
  time_s : float;
  dump_path : string option;
  source : string;
  vcid : string option;
}

type goal_tree_transition = {
  transition : string;
  source : string;
  succeeded : int;
  total : int;
  items : goal_tree_entry list;
}

type goal_tree_node = {
  node : string;
  source : string;
  succeeded : int;
  total : int;
  transitions : goal_tree_transition list;
}

type outline_request = {
  uri : string option;
  source_text : string option;
  abstract_text : string option;
}

type goals_tree_final_request = {
  goals : goal_info list;
  vc_sources : (int * string) list;
  vc_text : string;
}

type goals_tree_pending_request = {
  goal_names : string list;
  vc_ids : int list;
  vc_sources : (int * string) list;
}

type instrumentation_pass_request = {
  input_file : string;
  generate_png : bool;
  engine : string;
}

type why_pass_request = {
  input_file : string;
  prefix_fields : bool;
  engine : string;
}

type obligations_pass_request = {
  input_file : string;
  prover : string;
  prefix_fields : bool;
  engine : string;
}

type eval_pass_request = {
  input_file : string;
  trace_text : string;
  with_state : bool;
  with_locals : bool;
  engine : string;
}

type kobj_summary_request = {
  input_file : string;
  engine : string;
}

type dot_png_from_text_request = { dot_text : string }

type config = {
  input_file : string;
  engine : string;
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
}

val yojson_of_loc : loc -> Yojson.Safe.t
val loc_of_yojson : Yojson.Safe.t -> (loc, string) result

val yojson_of_goal_info : goal_info -> Yojson.Safe.t
val goal_info_of_yojson : Yojson.Safe.t -> (goal_info, string) result

val yojson_of_text_span : text_span -> Yojson.Safe.t
val text_span_of_yojson : Yojson.Safe.t -> (text_span, string) result

val yojson_of_proof_diagnostic : proof_diagnostic -> Yojson.Safe.t
val proof_diagnostic_of_yojson : Yojson.Safe.t -> (proof_diagnostic, string) result

val yojson_of_proof_trace : proof_trace -> Yojson.Safe.t
val proof_trace_of_yojson : Yojson.Safe.t -> (proof_trace, string) result

val yojson_of_outputs : outputs -> Yojson.Safe.t
val outputs_of_yojson : Yojson.Safe.t -> (outputs, string) result

val yojson_of_automata_outputs : automata_outputs -> Yojson.Safe.t
val automata_outputs_of_yojson : Yojson.Safe.t -> (automata_outputs, string) result

val yojson_of_why_outputs : why_outputs -> Yojson.Safe.t
val why_outputs_of_yojson : Yojson.Safe.t -> (why_outputs, string) result

val yojson_of_obligations_outputs : obligations_outputs -> Yojson.Safe.t
val obligations_outputs_of_yojson : Yojson.Safe.t -> (obligations_outputs, string) result

val yojson_of_rpc_request_id : rpc_request_id -> Yojson.Safe.t
val rpc_request_id_of_yojson : Yojson.Safe.t -> (rpc_request_id, string) result

val yojson_of_goals_ready_payload : goals_ready_payload -> Yojson.Safe.t
val goals_ready_payload_of_yojson : Yojson.Safe.t -> (goals_ready_payload, string) result

val yojson_of_goal_done_payload : goal_done_payload -> Yojson.Safe.t
val goal_done_payload_of_yojson : Yojson.Safe.t -> (goal_done_payload, string) result

val yojson_of_outputs_ready_notification : outputs_ready_notification -> Yojson.Safe.t
val outputs_ready_notification_of_yojson : Yojson.Safe.t -> (outputs_ready_notification, string) result

val yojson_of_goals_ready_notification : goals_ready_notification -> Yojson.Safe.t
val goals_ready_notification_of_yojson : Yojson.Safe.t -> (goals_ready_notification, string) result

val yojson_of_goal_done_notification : goal_done_notification -> Yojson.Safe.t
val goal_done_notification_of_yojson : Yojson.Safe.t -> (goal_done_notification, string) result

val yojson_of_outline_sections : outline_sections -> Yojson.Safe.t
val outline_sections_of_yojson : Yojson.Safe.t -> (outline_sections, string) result

val yojson_of_outline_payload : outline_payload -> Yojson.Safe.t
val outline_payload_of_yojson : Yojson.Safe.t -> (outline_payload, string) result

val yojson_of_goal_tree_entry : goal_tree_entry -> Yojson.Safe.t
val goal_tree_entry_of_yojson : Yojson.Safe.t -> (goal_tree_entry, string) result

val yojson_of_goal_tree_transition : goal_tree_transition -> Yojson.Safe.t
val goal_tree_transition_of_yojson : Yojson.Safe.t -> (goal_tree_transition, string) result

val yojson_of_goal_tree_node : goal_tree_node -> Yojson.Safe.t
val goal_tree_node_of_yojson : Yojson.Safe.t -> (goal_tree_node, string) result

val yojson_of_outline_request : outline_request -> Yojson.Safe.t
val outline_request_of_yojson : Yojson.Safe.t -> (outline_request, string) result

val yojson_of_goals_tree_final_request : goals_tree_final_request -> Yojson.Safe.t
val goals_tree_final_request_of_yojson : Yojson.Safe.t -> (goals_tree_final_request, string) result

val yojson_of_goals_tree_pending_request : goals_tree_pending_request -> Yojson.Safe.t
val goals_tree_pending_request_of_yojson : Yojson.Safe.t -> (goals_tree_pending_request, string) result

val yojson_of_instrumentation_pass_request : instrumentation_pass_request -> Yojson.Safe.t
val instrumentation_pass_request_of_yojson : Yojson.Safe.t -> (instrumentation_pass_request, string) result

val yojson_of_why_pass_request : why_pass_request -> Yojson.Safe.t
val why_pass_request_of_yojson : Yojson.Safe.t -> (why_pass_request, string) result

val yojson_of_obligations_pass_request : obligations_pass_request -> Yojson.Safe.t
val obligations_pass_request_of_yojson : Yojson.Safe.t -> (obligations_pass_request, string) result

val yojson_of_eval_pass_request : eval_pass_request -> Yojson.Safe.t
val eval_pass_request_of_yojson : Yojson.Safe.t -> (eval_pass_request, string) result

val yojson_of_kobj_summary_request : kobj_summary_request -> Yojson.Safe.t
val kobj_summary_request_of_yojson : Yojson.Safe.t -> (kobj_summary_request, string) result

val yojson_of_dot_png_from_text_request : dot_png_from_text_request -> Yojson.Safe.t
val dot_png_from_text_request_of_yojson : Yojson.Safe.t -> (dot_png_from_text_request, string) result

val yojson_of_config : config -> Yojson.Safe.t
val config_of_yojson : Yojson.Safe.t -> (config, string) result
