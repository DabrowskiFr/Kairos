include Kr_engine_pipeline_config
include Kr_engine_pipeline_proof_types
include Kr_engine_pipeline_artifacts

type diagnostic = Kr_engine_pipeline_error.diagnostic = {
  loc : source_location option;
  message : string;
}

type error = Kr_engine_pipeline_error.t =
  | Parse_error of diagnostic
  | Elaboration_error of diagnostic
  | Type_error of diagnostic
  | Well_formedness_error of diagnostic
  | Flow_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string
  | Internal_error of string

type verification_input = Kr_engine_inbound_port.verification_input
type generated_file = Kr_engine_inbound_port.generated_file = {
  file_name : string;
  contents : string;
}

let error_to_string = Kr_engine_pipeline_error.to_string

module type INBOUND = sig
  include Kr_engine_inbound_port.S
end
