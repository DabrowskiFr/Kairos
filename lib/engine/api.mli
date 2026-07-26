(** Stable in-process facade for clients embedding the Kairos engine.

    Delivery adapters depend on this facade instead of importing domain,
    backend, or runtime-orchestration modules. *)

module Types = Pipeline_types

type config = Types.config
type error = Types.error

val make_config :
  input_file:string ->
  wp_only:bool ->
  smoke_tests:bool ->
  timeout_s:int ->
  compute_proof_diagnostics:bool ->
  prove:bool ->
  ?proof_jobs:int ->
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
  (Types.automata_outputs, error) result

val why_pass : input_file:string -> (Types.why_outputs, error) result

val obligations_pass :
  input_file:string ->
  (Types.obligations_outputs, error) result

val normalized_program : input_file:string -> (string, error) result
val ir_pretty_dump : input_file:string -> (string, error) result
val run : config -> (Types.outputs, error) result

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  config ->
  on_outputs_ready:(Types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string option -> unit) ->
  (Types.outputs, error) result

type source_location

val source_location_line : source_location -> int
val source_location_column : source_location -> int
val source_location_end_line : source_location -> int
val source_location_end_column : source_location -> int
val proof_trace_source_location : Types.proof_trace -> source_location option
val output_vc_locations : Types.outputs -> (int * source_location) list
val output_ordered_vc_locations : Types.outputs -> source_location list

type source_diagnostic = {
  line : int;
  column : int;
  severity : int;
  source : string;
  message : string;
}

val source_diagnostics : text:string -> source_diagnostic list

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  variables : string list;
}

val semantic_symbols : text:string -> semantic_symbols option
