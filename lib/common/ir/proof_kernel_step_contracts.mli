(** Without-calls step-contract projection from symbolic kernel clauses. *)

val build_proof_step_contracts :
  product_steps:Proof_kernel_types.product_step_ir list ->
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  initial_product_state:Proof_kernel_types.product_state_ir ->
  symbolic_generated_clauses:Proof_kernel_types.relational_generated_clause_ir list ->
  Proof_kernel_types.proof_step_contract_ir list
