(** In-process facade for clients embedding the Kairos engine.

    Delivery adapters depend on this facade instead of importing domain,
    backend, or runtime-orchestration modules. *)

module Contract = Engine_contract

type config = Contract.config
type error = Contract.error

type source_diagnostic = {
  line : int;
  column : int;
  severity : int;
  source : string;
  message : string;
}

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  variables : string list;
}

type frontend_summary = {
  node_count : int;
  assume_count : int;
  guarantee_count : int;
}

type generated_file = {
  file_name : string;
  contents : string;
}

val make_config :
  input_file:string ->
  wp_only:bool ->
  smoke_tests:bool ->
  timeout_s:int ->
  compute_proof_diagnostics:bool ->
  prove:bool ->
  ?proof_jobs:int ->
  ?dump_failed_smt:bool ->
  ?collect_ir_metrics:bool ->
  ?proof_progress_path:string ->
  ?stop_on_first_nonvalid:bool ->
  ?proof_encoding:Contract.proof_encoding ->
  ?proof_optimizations:Contract.proof_optimizations ->
  generate_vc_text:bool ->
  generate_smt_text:bool ->
  generate_dot_png:bool ->
  unit ->
  config

val default_proof_jobs : unit -> int
val error_to_string : error -> string

val instrumentation_pass :
  generate_png:bool ->
  input_file:string ->
  (Contract.automata_outputs, error) result

val why_pass : input_file:string -> (Contract.why_outputs, error) result

val why_pass_with_options :
  proof_encoding:Contract.proof_encoding ->
  proof_optimizations:Contract.proof_optimizations ->
  input_file:string ->
  (Contract.why_outputs, error) result

val obligations_pass :
  input_file:string ->
  (Contract.obligations_outputs, error) result

val obligations_pass_with_options :
  proof_encoding:Contract.proof_encoding ->
  proof_optimizations:Contract.proof_optimizations ->
  input_file:string ->
  (Contract.obligations_outputs, error) result

val cost_report :
  proof_encoding:Contract.proof_encoding ->
  proof_optimizations:Contract.proof_optimizations ->
  input_file:string ->
  (Contract.cost_report_outputs, error) result

val normalized_program : input_file:string -> (string, error) result
val ir_pretty_dump : input_file:string -> (string, error) result

val normalized_program_with_options :
  proof_encoding:Contract.proof_encoding ->
  proof_optimizations:Contract.proof_optimizations ->
  input_file:string ->
  (string, error) result

val ir_pretty_dump_with_options :
  proof_encoding:Contract.proof_encoding ->
  proof_optimizations:Contract.proof_optimizations ->
  input_file:string ->
  (string, error) result

val run : config -> (Contract.outputs, error) result

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  config ->
  on_outputs_ready:(Contract.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string option -> unit) ->
  (Contract.outputs, error) result

val source_diagnostics : text:string -> source_diagnostic list

val semantic_symbols : text:string -> semantic_symbols option

val surface_dump : input_file:string -> (string, error) result
val elaborated_dump : input_file:string -> (string, error) result
val frontend_summary : input_file:string -> (frontend_summary, error) result

val generate_c : input_file:string -> (generated_file list, error) result
