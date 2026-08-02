(** Driven ports required by the engine's use cases.

    The engine owns these signatures. Concrete implementations live in
    outgoing adapters and are selected by the composition root. *)

type verification_input = {
  parse_info : Flow_info.parse_info;
  verification_model : Verification_model.program_model;
}
(** Language-independent input produced before entering the engine. *)

type generated_file = { file_name : string; contents : string }

val make_verification_input :
  source_path:string option ->
  text_hash:string option ->
  warnings:string list ->
  verification_model:Verification_model.program_model ->
  verification_input
(** Build the neutral engine input at an incoming-adapter boundary. *)

module type PIPELINE = sig
  val instrumentation_pass :
    generate_png:bool ->
    input:verification_input ->
    (Pipeline_artifacts.automata_outputs, Pipeline_error.t) result

  val why_pass :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:verification_input ->
    (Pipeline_artifacts.why_outputs, Pipeline_error.t) result

  val obligations_pass :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:verification_input ->
    (Pipeline_artifacts.obligations_outputs, Pipeline_error.t) result

  val cost_report :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:verification_input ->
    (Pipeline_artifacts.cost_report_outputs, Pipeline_error.t) result

  val normalized_program :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:verification_input ->
    (string, Pipeline_error.t) result

  val ir_pretty_dump :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:verification_input ->
    (string, Pipeline_error.t) result

  val run :
    input:verification_input ->
    Pipeline_config.config ->
    (Pipeline_artifacts.outputs, Pipeline_error.t) result

  val run_with_callbacks :
    should_cancel:(unit -> bool) ->
    input:verification_input ->
    Pipeline_config.config ->
    on_outputs_ready:(Pipeline_artifacts.outputs -> unit) ->
    on_goals_ready:(string list * int list -> unit) ->
    on_goal_done:
      (int -> string -> string -> float -> string option -> string option -> unit) ->
    (Pipeline_artifacts.outputs, Pipeline_error.t) result

  val generate_c :
    input:verification_input ->
    (generated_file list, Pipeline_error.t) result
end

module type S = sig
  module Pipeline : PIPELINE
end
