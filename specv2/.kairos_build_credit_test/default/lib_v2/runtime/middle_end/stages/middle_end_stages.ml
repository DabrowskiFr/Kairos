open Ast
module Automata_generation = Automata_pass.Pass
module Contracts = Contracts_pass.Pass
module Instrumentation = Instrumentation_pass.Pass

type automata_stage = Automata_pass_sig.stage

let stage_automata_generation_with_info (p : Stage_types.parsed) :
    Stage_types.parsed * automata_stage * Stage_info.automata_info =
  Automata_generation.run_with_info p ()

let stage_automata_generation (p : Stage_types.parsed) :
    Stage_types.parsed * automata_stage =
  Automata_generation.run p ()

let stage_contracts_with_info ((p, automata) : Stage_types.instrumentation_stage * automata_stage) :
    Stage_types.contracts_stage * automata_stage * Stage_info.contracts_info =
  Contracts.run_with_info p automata

let stage_contracts ((p, automata) : Stage_types.instrumentation_stage * automata_stage) :
    Stage_types.contracts_stage * automata_stage =
  Contracts.run p automata

let stage_instrumentation_with_info ((p, automata) : Stage_types.parsed * automata_stage) :
    Stage_types.instrumentation_stage * automata_stage * Stage_info.instrumentation_info =
  Instrumentation.run_with_info p automata

let stage_instrumentation ((p, automata) : Stage_types.parsed * automata_stage) :
    Stage_types.instrumentation_stage * automata_stage =
  Instrumentation.run p automata

let run (p : Stage_types.parsed) : Stage_types.contracts_stage * automata_stage =
  let p, automata = stage_automata_generation p in
  let p, automata = stage_instrumentation (p, automata) in
  stage_contracts (p, automata)
