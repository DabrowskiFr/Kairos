(** Stable names and labels for generated Why3 product-step helpers. *)

val product_step_helper_name :
  node_name:Kr_domain_core_syntax.ident ->
  index:int ->
  Kr_verification.Kr_verification_step_contract.step_contract ->
  string

val product_step_group_helper_name :
  node_name:Kr_domain_core_syntax.ident ->
  index:int ->
  Kr_verification.Kr_verification_step_contract.step_contract ->
  string
