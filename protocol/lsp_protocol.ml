type loc = { line : int; col : int; line_end : int; col_end : int } [@@deriving yojson]

type goal_info = string * string * float * string option * string * string option [@@deriving yojson]

type text_span = {
  start_offset : int;
  end_offset : int;
}
[@@deriving yojson]

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
[@@deriving yojson]

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
[@@deriving yojson]

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
}
[@@deriving yojson]

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
}
[@@deriving yojson]

type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }
[@@deriving yojson]

type obligations_outputs = { vc_text : string; smt_text : string } [@@deriving yojson]

type rpc_request_id =
  | Rpc_int_id of int
  | Rpc_string_id of string

let rpc_request_id_to_yojson = function
  | Rpc_int_id i -> `Int i
  | Rpc_string_id s -> `String s

let rpc_request_id_of_yojson = function
  | `Int i -> Ok (Rpc_int_id i)
  | `String s -> Ok (Rpc_string_id s)
  | _ -> Error "Expected JSON-RPC id"

let yojson_of_rpc_request_id = rpc_request_id_to_yojson

type goals_ready_payload = { names : string list; vc_ids : int list [@key "vcIds"] } [@@deriving yojson]

type goal_done_payload = {
  idx : int;
  goal : string;
  status : string;
  time_s : float;
  dump_path : string option;
  source : string;
  vcid : string option;
}
[@@deriving yojson]

type outputs_ready_notification = {
  request_id : rpc_request_id [@key "requestId"];
  payload : outputs;
}
[@@deriving yojson]

type goals_ready_notification = {
  request_id : rpc_request_id [@key "requestId"];
  payload : goals_ready_payload;
}
[@@deriving yojson]

type goal_done_notification = {
  request_id : rpc_request_id [@key "requestId"];
  payload : goal_done_payload;
}
[@@deriving yojson]

type outline_sections = {
  nodes : (string * int) list;
  transitions : (string * int) list;
  contracts : (string * int) list;
}
[@@deriving yojson]

type outline_payload = {
  source : outline_sections;
  abstract_program : outline_sections [@key "abstract"];
}
[@@deriving yojson]

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
[@@deriving yojson]

type goal_tree_transition = {
  transition : string;
  source : string;
  succeeded : int;
  total : int;
  items : goal_tree_entry list;
}
[@@deriving yojson]

type goal_tree_node = {
  node : string;
  source : string;
  succeeded : int;
  total : int;
  transitions : goal_tree_transition list;
}
[@@deriving yojson]

type outline_request = {
  uri : string option;
  source_text : string option [@key "sourceText"];
  abstract_text : string option [@key "abstractText"];
}
[@@deriving yojson]

type goals_tree_final_request = {
  goals : goal_info list;
  vc_sources : (int * string) list [@key "vcSources"];
  vc_text : string [@key "vcText"];
}
[@@deriving yojson]

type goals_tree_pending_request = {
  goal_names : string list [@key "goalNames"];
  vc_ids : int list [@key "vcIds"];
  vc_sources : (int * string) list [@key "vcSources"];
}
[@@deriving yojson]

type instrumentation_pass_request = {
  input_file : string [@key "inputFile"];
  generate_png : bool [@key "generatePng"];
  engine : string;
}
[@@deriving yojson]

type why_pass_request = {
  input_file : string [@key "inputFile"];
  prefix_fields : bool [@key "prefixFields"];
  engine : string;
}
[@@deriving yojson]

type obligations_pass_request = {
  input_file : string [@key "inputFile"];
  prover : string;
  prefix_fields : bool [@key "prefixFields"];
  engine : string;
}
[@@deriving yojson]

type eval_pass_request = {
  input_file : string [@key "inputFile"];
  trace_text : string [@key "traceText"];
  with_state : bool [@key "withState"];
  with_locals : bool [@key "withLocals"];
  engine : string;
}
[@@deriving yojson]

type dot_png_from_text_request = { dot_text : string [@key "dotText"] } [@@deriving yojson]

type config_repr = {
  input_file : string;
  engine : string option;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  max_proof_goals : int option;
  selected_goal_index : int option;
  compute_proof_diagnostics : bool;
  prefix_fields : bool;
  prove : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_monitor_text : bool;
  generate_dot_png : bool;
}
[@@deriving yojson]

type config = {
  input_file : string;
  engine : string;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  max_proof_goals : int option;
  selected_goal_index : int option;
  compute_proof_diagnostics : bool;
  prefix_fields : bool;
  prove : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_monitor_text : bool;
  generate_dot_png : bool;
}

let yojson_of_config (c : config) =
  let repr : config_repr =
    {
      input_file = c.input_file;
      engine = Some c.engine;
      prover = c.prover;
      prover_cmd = c.prover_cmd;
      wp_only = c.wp_only;
      smoke_tests = c.smoke_tests;
      timeout_s = c.timeout_s;
      max_proof_goals = c.max_proof_goals;
      selected_goal_index = c.selected_goal_index;
      compute_proof_diagnostics = c.compute_proof_diagnostics;
      prefix_fields = c.prefix_fields;
      prove = c.prove;
      generate_vc_text = c.generate_vc_text;
      generate_smt_text = c.generate_smt_text;
      generate_monitor_text = c.generate_monitor_text;
        generate_dot_png = c.generate_dot_png;
    }
  in
  config_repr_to_yojson repr

let config_of_yojson json =
  match config_repr_of_yojson json with
  | Error _ as e -> e
  | Ok (repr : config_repr) ->
      Ok
        {
          input_file = repr.input_file;
          engine = Option.value repr.engine ~default:"v2";
          prover = repr.prover;
          prover_cmd = repr.prover_cmd;
          wp_only = repr.wp_only;
          smoke_tests = repr.smoke_tests;
          timeout_s = repr.timeout_s;
          max_proof_goals = repr.max_proof_goals;
          selected_goal_index = repr.selected_goal_index;
          compute_proof_diagnostics = repr.compute_proof_diagnostics;
          prefix_fields = repr.prefix_fields;
          prove = repr.prove;
          generate_vc_text = repr.generate_vc_text;
          generate_smt_text = repr.generate_smt_text;
          generate_monitor_text = repr.generate_monitor_text;
          generate_dot_png = repr.generate_dot_png;
        }

let yojson_of_loc = loc_to_yojson
let loc_of_yojson = loc_of_yojson

let yojson_of_goal_info = goal_info_to_yojson
let goal_info_of_yojson = goal_info_of_yojson

let yojson_of_text_span = text_span_to_yojson
let text_span_of_yojson = text_span_of_yojson

let yojson_of_proof_diagnostic = proof_diagnostic_to_yojson
let proof_diagnostic_of_yojson = proof_diagnostic_of_yojson

let yojson_of_proof_trace = proof_trace_to_yojson
let proof_trace_of_yojson = proof_trace_of_yojson

let yojson_of_outputs = outputs_to_yojson
let outputs_of_yojson = outputs_of_yojson

let yojson_of_automata_outputs = automata_outputs_to_yojson
let automata_outputs_of_yojson = automata_outputs_of_yojson

let yojson_of_why_outputs = why_outputs_to_yojson
let why_outputs_of_yojson = why_outputs_of_yojson

let yojson_of_obligations_outputs = obligations_outputs_to_yojson
let obligations_outputs_of_yojson = obligations_outputs_of_yojson

let yojson_of_goals_ready_payload = goals_ready_payload_to_yojson
let goals_ready_payload_of_yojson = goals_ready_payload_of_yojson

let yojson_of_goal_done_payload = goal_done_payload_to_yojson
let goal_done_payload_of_yojson = goal_done_payload_of_yojson

let yojson_of_outputs_ready_notification = outputs_ready_notification_to_yojson
let outputs_ready_notification_of_yojson = outputs_ready_notification_of_yojson

let yojson_of_goals_ready_notification = goals_ready_notification_to_yojson
let goals_ready_notification_of_yojson = goals_ready_notification_of_yojson

let yojson_of_goal_done_notification = goal_done_notification_to_yojson
let goal_done_notification_of_yojson = goal_done_notification_of_yojson

let yojson_of_outline_sections = outline_sections_to_yojson
let outline_sections_of_yojson = outline_sections_of_yojson

let yojson_of_outline_payload = outline_payload_to_yojson
let outline_payload_of_yojson = outline_payload_of_yojson

let yojson_of_goal_tree_entry = goal_tree_entry_to_yojson
let goal_tree_entry_of_yojson = goal_tree_entry_of_yojson

let yojson_of_goal_tree_transition = goal_tree_transition_to_yojson
let goal_tree_transition_of_yojson = goal_tree_transition_of_yojson

let yojson_of_goal_tree_node = goal_tree_node_to_yojson
let goal_tree_node_of_yojson = goal_tree_node_of_yojson

let yojson_of_outline_request = outline_request_to_yojson
let outline_request_of_yojson = outline_request_of_yojson

let yojson_of_goals_tree_final_request = goals_tree_final_request_to_yojson
let goals_tree_final_request_of_yojson = goals_tree_final_request_of_yojson

let yojson_of_goals_tree_pending_request = goals_tree_pending_request_to_yojson
let goals_tree_pending_request_of_yojson = goals_tree_pending_request_of_yojson

let yojson_of_instrumentation_pass_request = instrumentation_pass_request_to_yojson
let instrumentation_pass_request_of_yojson = instrumentation_pass_request_of_yojson

let yojson_of_why_pass_request = why_pass_request_to_yojson
let why_pass_request_of_yojson = why_pass_request_of_yojson

let yojson_of_obligations_pass_request = obligations_pass_request_to_yojson
let obligations_pass_request_of_yojson = obligations_pass_request_of_yojson

let yojson_of_eval_pass_request = eval_pass_request_to_yojson
let eval_pass_request_of_yojson = eval_pass_request_of_yojson

let yojson_of_dot_png_from_text_request = dot_png_from_text_request_to_yojson
let dot_png_from_text_request_of_yojson = dot_png_from_text_request_of_yojson
