(** Public assembly of the engine's narrow pipeline contracts.

    Internal engine modules depend on the narrow modules directly. *)

include Pipeline_config
include Pipeline_proof_types
include Pipeline_artifacts

type error = Pipeline_error.t =
  | Parse_error of string
  | Elaboration_error of string
  | Type_error of string
  | Well_formedness_error of string
  | Flow_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string
  | Internal_error of string

let error_to_string = Pipeline_error.to_string
