(** Stable names and labels for generated Why3 product-step helpers. *)

val product_step_helper_name :
  index:int ->
  Kairos_verification_obligations.Step_contract_projection.step_contract ->
  string

val product_step_group_helper_name :
  index:int ->
  Kairos_verification_obligations.Step_contract_projection.step_contract ->
  string
