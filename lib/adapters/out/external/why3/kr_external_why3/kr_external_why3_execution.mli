(** Execute structured WhyML proof requests. *)

module Contract = Kr_why3_contract.Kr_why3_contract_contract

val execute_ptree :
  ?should_cancel:(unit -> bool) ->
  ?on_progress:(string -> unit) ->
  ?on_warning:(string -> unit) ->
  ?on_goal_start:(Contract.goal_descriptor -> unit) ->
  ?on_goal_done:(Contract.goal_result -> unit) ->
  options:Contract.execution_options ->
  Why3.Ptree.mlw_file ->
  Contract.execution_response
(** It typechecks the supplied parse tree directly and performs no WhyML printing or parsing. *)
