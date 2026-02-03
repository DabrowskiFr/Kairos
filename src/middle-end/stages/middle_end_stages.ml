open Ast

let stage_automaton (p:program) : program =
  List.map Monitor_instrument.pass_automaton_only p

let stage_contracts (p:program) : program =
  List.map Contract_link.user_contracts_coherency p

let stage_monitor_injection (p:program) : program =
  List.map Monitor_instrument.transform_node_monitor p

let run (p:program) : program =
  p
  |> stage_automaton
  |> stage_contracts
  |> stage_monitor_injection
