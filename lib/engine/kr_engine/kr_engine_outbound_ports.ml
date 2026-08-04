module type VERIFICATION = sig
  val instrumentation_pass :
    generate_png:bool ->
    input:Kr_engine_inbound_port.verification_input ->
    (Kr_engine_pipeline_artifacts.automata_outputs, Kr_engine_pipeline_error.t) result

  val why_pass :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:Kr_engine_inbound_port.verification_input ->
    (Kr_engine_pipeline_artifacts.why_outputs, Kr_engine_pipeline_error.t) result

  val obligations_pass :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:Kr_engine_inbound_port.verification_input ->
    (Kr_engine_pipeline_artifacts.obligations_outputs, Kr_engine_pipeline_error.t) result

  val cost_report :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:Kr_engine_inbound_port.verification_input ->
    (Kr_engine_pipeline_artifacts.cost_report_outputs, Kr_engine_pipeline_error.t) result

  val normalized_program :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:Kr_engine_inbound_port.verification_input ->
    (string, Kr_engine_pipeline_error.t) result

  val ir_pretty_dump :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:Kr_engine_inbound_port.verification_input ->
    (string, Kr_engine_pipeline_error.t) result

  val run :
    input:Kr_engine_inbound_port.verification_input ->
    Kr_engine_pipeline_config.config ->
    (Kr_engine_pipeline_artifacts.outputs, Kr_engine_pipeline_error.t) result

  val run_with_callbacks :
    should_cancel:(unit -> bool) ->
    input:Kr_engine_inbound_port.verification_input ->
    Kr_engine_pipeline_config.config ->
    on_outputs_ready:(Kr_engine_pipeline_artifacts.outputs -> unit) ->
    on_goals_ready:(string list * int list -> unit) ->
    on_goal_done:
      (int -> string -> string -> float -> string option -> string option -> unit) ->
    (Kr_engine_pipeline_artifacts.outputs, Kr_engine_pipeline_error.t) result
end

module type C_GENERATION = sig
  val generate_c :
    input:Kr_engine_inbound_port.verification_input ->
    (Kr_engine_inbound_port.generated_file list, Kr_engine_pipeline_error.t) result
end

module type S = sig
  module Verification : VERIFICATION
  module C_generation : C_GENERATION
end
