(** Outbound ports required by the engine's use cases.

    The engine owns these signatures. Concrete implementations live in
    outgoing adapters and are selected by the composition root. *)

module type VERIFICATION = sig
  (** Execute verification and inspection operations after an incoming adapter
      has produced a language-independent engine input. *)

  val instrumentation_pass :
    generate_png:bool ->
    input:Inbound_port.verification_input ->
    (Pipeline_artifacts.automata_outputs, Pipeline_error.t) result

  val why_pass :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:Inbound_port.verification_input ->
    (Pipeline_artifacts.why_outputs, Pipeline_error.t) result

  val obligations_pass :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:Inbound_port.verification_input ->
    (Pipeline_artifacts.obligations_outputs, Pipeline_error.t) result

  val cost_report :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:Inbound_port.verification_input ->
    (Pipeline_artifacts.cost_report_outputs, Pipeline_error.t) result

  val normalized_program :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:Inbound_port.verification_input ->
    (string, Pipeline_error.t) result

  val ir_pretty_dump :
    proof_optimizations:Pipeline_config.proof_optimizations ->
    input:Inbound_port.verification_input ->
    (string, Pipeline_error.t) result

  val run :
    input:Inbound_port.verification_input ->
    Pipeline_config.config ->
    (Pipeline_artifacts.outputs, Pipeline_error.t) result

  val run_with_callbacks :
    should_cancel:(unit -> bool) ->
    input:Inbound_port.verification_input ->
    Pipeline_config.config ->
    on_outputs_ready:(Pipeline_artifacts.outputs -> unit) ->
    on_goals_ready:(string list * int list -> unit) ->
    on_goal_done:
      (int -> string -> string -> float -> string option -> string option -> unit) ->
    (Pipeline_artifacts.outputs, Pipeline_error.t) result

end

module type C_GENERATION = sig
  (** Generate executable C artifacts from the normalized program. *)

  val generate_c :
    input:Inbound_port.verification_input ->
    (Inbound_port.generated_file list, Pipeline_error.t) result
end

module type S = sig
  module Verification : VERIFICATION
  module C_generation : C_GENERATION
end
