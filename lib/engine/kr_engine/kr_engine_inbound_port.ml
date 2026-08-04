type verification_input = {
  parse_info : Kr_engine_flow_info.parse_info;
  verification_model : Kr_domain_core_model.program_model;
}

type generated_file = { file_name : string; contents : string }

let make_verification_input ~source_path ~text_hash ~warnings
    ~verification_model =
  {
    parse_info = { Kr_engine_flow_info.source_path; text_hash; warnings };
    verification_model;
  }

module type S = sig
  val instrumentation_pass :
    generate_png:bool ->
    input:verification_input ->
    (Kr_engine_pipeline_artifacts.automata_outputs, Kr_engine_pipeline_error.t) result

  val why_pass :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:verification_input ->
    (Kr_engine_pipeline_artifacts.why_outputs, Kr_engine_pipeline_error.t) result

  val obligations_pass :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:verification_input ->
    (Kr_engine_pipeline_artifacts.obligations_outputs, Kr_engine_pipeline_error.t) result

  val cost_report :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:verification_input ->
    (Kr_engine_pipeline_artifacts.cost_report_outputs, Kr_engine_pipeline_error.t) result

  val normalized_program :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:verification_input ->
    (string, Kr_engine_pipeline_error.t) result

  val ir_pretty_dump :
    proof_optimizations:Kr_engine_pipeline_config.proof_optimizations ->
    input:verification_input ->
    (string, Kr_engine_pipeline_error.t) result

  val run :
    input:verification_input ->
    Kr_engine_pipeline_config.config ->
    (Kr_engine_pipeline_artifacts.outputs, Kr_engine_pipeline_error.t) result

  val run_with_callbacks :
    should_cancel:(unit -> bool) ->
    input:verification_input ->
    Kr_engine_pipeline_config.config ->
    on_outputs_ready:(Kr_engine_pipeline_artifacts.outputs -> unit) ->
    on_goals_ready:(string list * int list -> unit) ->
    on_goal_done:
      (int -> string -> string -> float -> string option -> string option -> unit) ->
    (Kr_engine_pipeline_artifacts.outputs, Kr_engine_pipeline_error.t) result

  val generate_c :
    input:verification_input ->
    (generated_file list, Kr_engine_pipeline_error.t) result
end
