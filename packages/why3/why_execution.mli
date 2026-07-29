(** Execute structured WhyML proof requests. *)

module Contract = Kairos_why3_contract.Why3_contract

val execute_ptree :
  ?should_cancel:(unit -> bool) ->
  ?on_goal_start:(Contract.goal_descriptor -> unit) ->
  ?on_goal_done:(Contract.goal_result -> unit) ->
  options:Contract.execution_options ->
  Why3.Ptree.mlw_file ->
  Contract.execution_response
(** It typechecks the supplied parse tree directly and performs no WhyML printing or parsing. *)
