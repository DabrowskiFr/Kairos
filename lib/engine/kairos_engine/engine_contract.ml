(** Public assembly of the engine's narrow pipeline contracts.

    Internal engine modules depend on the narrow modules directly. *)

include Pipeline_config
include Pipeline_proof_types
include Pipeline_artifacts

type diagnostic = Pipeline_error.diagnostic = {
  loc : source_location option;
  message : string;
}

type error = Pipeline_error.t =
  | Parse_error of diagnostic
  | Elaboration_error of diagnostic
  | Type_error of diagnostic
  | Well_formedness_error of diagnostic
  | Flow_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string
  | Internal_error of string

let error_to_string = Pipeline_error.to_string
