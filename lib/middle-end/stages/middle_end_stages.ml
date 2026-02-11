open Ast
module Monitor_generation = Monitor_generation_pass.Pass
module Contracts = Contracts_pass.Pass
module Monitor = Monitor_pass.Pass

type monitor_generation_stage = Monitor_generation_pass_sig.stage

let stage_monitor_generation_with_info (p : Stage_types.parsed) :
    Stage_types.parsed * monitor_generation_stage * Stage_info.monitor_generation_info =
  Monitor_generation.run_with_info p ()

let stage_monitor_generation (p : Stage_types.parsed) :
    Stage_types.parsed * monitor_generation_stage =
  Monitor_generation.run p ()

let stage_contracts_with_info ((p, automata) : Stage_types.parsed * monitor_generation_stage) :
    Stage_types.contracts_stage * monitor_generation_stage * Stage_info.contracts_info =
  Contracts.run_with_info p automata

let stage_contracts ((p, automata) : Stage_types.parsed * monitor_generation_stage) :
    Stage_types.contracts_stage * monitor_generation_stage =
  Contracts.run p automata

let stage_monitor_injection_with_info
    ((p, automata) : Stage_types.contracts_stage * monitor_generation_stage) :
    Stage_types.monitor_stage * monitor_generation_stage * Stage_info.monitor_info =
  Monitor.run_with_info p automata

let stage_monitor_injection ((p, automata) : Stage_types.contracts_stage * monitor_generation_stage)
    : Stage_types.monitor_stage * monitor_generation_stage =
  Monitor.run p automata

let run (p : Stage_types.parsed) : Stage_types.monitor_stage * monitor_generation_stage =
  let p, automata = stage_monitor_generation p in
  let p, automata = stage_contracts (p, automata) in
  stage_monitor_injection (p, automata)
