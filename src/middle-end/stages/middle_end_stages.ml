open Ast

module Automaton : Automaton_pass.S = Automaton_default
module Contracts = Contracts_pass.Pass
module Monitor = Monitor_pass.Pass

type automaton_stage = Automaton_pass.stage

let stage_automaton_with_info (p:Stage_types.parsed)
  : Stage_types.parsed * automaton_stage * Stage_info.automaton_info =
  Automaton.run_with_info p ()

let stage_automaton (p:Stage_types.parsed)
  : Stage_types.parsed * automaton_stage =
  Automaton.run p ()

let stage_contracts_with_info ((p, automata):Stage_types.parsed * automaton_stage)
  : Stage_types.contracts_stage * automaton_stage * Stage_info.contracts_info =
  Contracts.run_with_info p automata

let stage_contracts ((p, automata):Stage_types.parsed * automaton_stage)
  : Stage_types.contracts_stage * automaton_stage =
  Contracts.run p automata

let stage_monitor_injection_with_info ((p, automata):Stage_types.contracts_stage * automaton_stage)
  : Stage_types.monitor_stage * automaton_stage * Stage_info.monitor_info =
  Monitor.run_with_info p automata

let stage_monitor_injection ((p, automata):Stage_types.contracts_stage * automaton_stage)
  : Stage_types.monitor_stage * automaton_stage =
  Monitor.run p automata

let run (p:Stage_types.parsed) : Stage_types.monitor_stage * automaton_stage =
  let p, automata = stage_automaton p in
  let p, automata = stage_contracts (p, automata) in
  stage_monitor_injection (p, automata)
