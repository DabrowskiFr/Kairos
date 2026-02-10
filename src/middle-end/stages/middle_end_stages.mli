val stage_automaton : Stage_types.parsed -> Stage_types.automaton_stage
(** Build the monitor automaton (atoms -> automaton -> inline atoms). *)
val stage_automaton_with_info :
  Stage_types.parsed -> Stage_types.automaton_stage * Stage_info.automaton_info

val stage_contracts : Stage_types.automaton_stage -> Stage_types.contracts_stage
(** Add user contract coherency constraints. *)
val stage_contracts_with_info :
  Stage_types.automaton_stage -> Stage_types.contracts_stage * Stage_info.contracts_info

val stage_monitor_injection :
  Stage_types.contracts_stage -> Stage_types.monitor_stage
(** Inject monitor-related contracts into transitions. *)
val stage_monitor_injection_with_info :
  Stage_types.contracts_stage -> Stage_types.monitor_stage * Stage_info.monitor_info

val run : Stage_types.parsed -> Stage_types.monitor_stage
(** Compose all middle-end stages in order. *)
