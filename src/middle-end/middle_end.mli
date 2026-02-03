val stage_automaton : Stage_types.parsed -> Stage_types.automaton_stage
val stage_contracts : Stage_types.automaton_stage -> Stage_types.contracts_stage
val stage_monitor_injection : Stage_types.contracts_stage -> Stage_types.monitor_stage
val run : Stage_types.parsed -> Stage_types.monitor_stage
