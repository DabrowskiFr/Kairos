(** Execute a neutral WhyML proof request without exposing Why3 values. *)

module Contract = Kairos_proof_contract.Proof_backend_contract

val execute :
  ?should_cancel:(unit -> bool) ->
  ?on_goal_start:(Contract.goal_descriptor -> unit) ->
  ?on_goal_done:(Contract.goal_result -> unit) ->
  Contract.execution_request ->
  Contract.execution_response
