(* Per‑goal status tuple for UI: (name, status, time, prover, source, message). *)
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

(* Aggregated outputs returned by [run]. *)
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
}

(* Outputs of the instrumentation‑only pass. *)
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

(* Outputs of the Why3 pass (text + stage meta). *)
type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }

(* Outputs of the VC/SMT export pass. *)
type obligations_outputs = { vc_text : string; smt_text : string }

(* AST snapshots per stage (used by IDE/diagnostics). *)
type ast_stages = {
  source : Source_file.t;
  parsed : Ast.program;
  automata_generation : Ast.program;
  automata : Middle_end_stages.automata_stage;
  contracts : Ast.program;
  instrumentation : Ast.program;
  imported_summaries : Product_kernel_ir.exported_node_summary_ir list;
}

(* Stage metadata aggregated from passes. *)
type stage_infos = {
  parse : Stage_info.parse_info option;
  automata_generation : Stage_info.automata_info option;
  contracts : Stage_info.contracts_info option;
  instrumentation : Stage_info.instrumentation_info option;
}

(* Pipeline configuration flags. *)
type config = {
  input_file : string;
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

(* Errors returned by pipeline entry points. *)
type error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

(* Render an error as a human‑readable message. *)
val error_to_string : error -> string

(* Build the full AST pipeline (no extra metadata). *)
val build_ast : ?log:bool -> input_file:string -> unit -> (ast_stages, error) result

(* Build the full AST pipeline and collect stage metadata. *)
val build_ast_with_info :
  ?log:bool -> input_file:string -> unit -> (ast_stages * stage_infos, error) result

(* Render the four graph PNG artefacts when DOT text is available. *)
val graph_pngs :
  program_dot:string ->
  guarantee_automaton_dot:string ->
  assume_automaton_dot:string ->
  product_dot:string ->
  string option * string option * string option * string option

val build_vcid_locs : Ast.program -> (int * Ast.loc) list * Ast.loc list

(* Run the instrumentation‑only pass (dot + labels). *)
val instrumentation_pass : generate_png:bool -> input_file:string -> (automata_outputs, error) result

(* Run the Why3 text pass. *)
val why_pass : prefix_fields:bool -> input_file:string -> (why_outputs, error) result

(* Run VC/SMT exports. *)
val obligations_pass :
  prefix_fields:bool -> prover:string -> input_file:string -> (obligations_outputs, error) result

(* Evaluate one top-level Kairos node on an input trace.
   Supported trace formats (auto-detected):
   - assignments: one step per line, "x=1, y=true"
   - CSV: header row with input names, then one row per step
   - JSONL: one JSON object per step, e.g. {"x":1,"y":true} *)
val eval_pass :
  input_file:string ->
  trace_text:string ->
  with_state:bool ->
  with_locals:bool ->
  (string, error) result

(* Full end‑to‑end pipeline run. *)
val run : config -> (outputs, error) result

(* Pipeline run with incremental callbacks for the IDE. *)
val run_with_callbacks :
  ?should_cancel:(unit -> bool) ->
  config ->
  on_outputs_ready:(outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (outputs, error) result

(* Render DOT text to a PNG (if Graphviz is available). *)
val dot_png_from_text : string -> string option
val dot_png_from_text_diagnostic : string -> string option * string option
