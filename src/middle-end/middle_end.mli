val stage_automaton :
  Stage_types.parsed -> Stage_types.parsed * Middle_end_stages.automaton_stage
val stage_automaton_with_info :
  Stage_types.parsed ->
  Stage_types.parsed * Middle_end_stages.automaton_stage * Stage_info.automaton_info
val stage_contracts :
  Stage_types.parsed * Middle_end_stages.automaton_stage ->
  Stage_types.contracts_stage * Middle_end_stages.automaton_stage
val stage_contracts_with_info :
  Stage_types.parsed * Middle_end_stages.automaton_stage ->
  Stage_types.contracts_stage * Middle_end_stages.automaton_stage * Stage_info.contracts_info
val stage_monitor_injection :
  Stage_types.contracts_stage * Middle_end_stages.automaton_stage ->
  Stage_types.monitor_stage * Middle_end_stages.automaton_stage
val stage_monitor_injection_with_info :
  Stage_types.contracts_stage * Middle_end_stages.automaton_stage ->
  Stage_types.monitor_stage * Middle_end_stages.automaton_stage * Stage_info.monitor_info
val run : Stage_types.parsed -> Stage_types.monitor_stage * Middle_end_stages.automaton_stage
