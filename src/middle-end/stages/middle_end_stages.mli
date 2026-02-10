(** Automaton stage implementation (swappable). *)
module Automaton : Automaton_pass.S

module Contracts :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.contracts_stage
     and type stage_in = Automaton_pass.stage
     and type stage_out = Automaton_pass.stage
     and type info = Stage_info.contracts_info

module Monitor :
  Middle_end_pass.S
    with type ast_in = Stage_types.contracts_stage
     and type ast_out = Stage_types.monitor_stage
     and type stage_in = Automaton_pass.stage
     and type stage_out = Automaton_pass.stage
     and type info = Stage_info.monitor_info

type automaton_stage = Automaton_pass.stage

val stage_automaton : Stage_types.parsed -> Stage_types.parsed * automaton_stage
(** Build the monitor automaton (atoms -> automaton -> inline atoms). *)
val stage_automaton_with_info :
  Stage_types.parsed ->
  Stage_types.parsed * automaton_stage * Stage_info.automaton_info

val stage_contracts :
  Stage_types.parsed * automaton_stage ->
  Stage_types.contracts_stage * automaton_stage
(** Add user contract coherency constraints. *)
val stage_contracts_with_info :
  Stage_types.parsed * automaton_stage ->
  Stage_types.contracts_stage * automaton_stage * Stage_info.contracts_info

val stage_monitor_injection :
  Stage_types.contracts_stage * automaton_stage ->
  Stage_types.monitor_stage * automaton_stage
(** Inject monitor-related contracts into transitions. *)
val stage_monitor_injection_with_info :
  Stage_types.contracts_stage * automaton_stage ->
  Stage_types.monitor_stage * automaton_stage * Stage_info.monitor_info

val run : Stage_types.parsed -> Stage_types.monitor_stage * automaton_stage
(** Compose all middle-end stages in order. *)
