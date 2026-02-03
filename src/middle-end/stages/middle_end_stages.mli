val stage_automaton : Stage_types.parsed -> Stage_types.automaton_stage
(** Build the monitor automaton (atoms -> automaton -> inline atoms). *)

val stage_contracts : Stage_types.automaton_stage -> Stage_types.contracts_stage
(** Add user contract coherency constraints. *)

val stage_monitor_injection :
  Stage_types.contracts_stage -> Stage_types.monitor_stage
(** Inject monitor-related contracts into transitions. *)

val run : Stage_types.parsed -> Stage_types.monitor_stage
(** Compose all middle-end stages in order. *)
