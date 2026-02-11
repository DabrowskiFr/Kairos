(* Middle‑end stage implementations wired into the pipeline. *)

(* Monitor generation stage implementation (swappable). *)
module Monitor_generation :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.parsed
     and type stage_in = unit
     and type stage_out = Monitor_generation_pass_sig.stage
     and type info = Stage_info.monitor_generation_info

(* Contracts pass: adds coherency/compatibility constraints. *)
module Contracts :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.contracts_stage
     and type stage_in = Monitor_generation_pass_sig.stage
     and type stage_out = Monitor_generation_pass_sig.stage
     and type info = Stage_info.contracts_info

(* Monitor injection pass: instruments transitions using automata. *)
module Monitor :
  Middle_end_pass.S
    with type ast_in = Stage_types.contracts_stage
     and type ast_out = Stage_types.monitor_stage
     and type stage_in = Monitor_generation_pass_sig.stage
     and type stage_out = Monitor_generation_pass_sig.stage
     and type info = Stage_info.monitor_info

(* Stage artifact carrying per‑node automata. *)
type monitor_generation_stage = Monitor_generation_pass_sig.stage

(* Build the monitor automaton (atoms → automaton → inline atoms). *)
val stage_monitor_generation : Stage_types.parsed -> Stage_types.parsed * monitor_generation_stage

(* Build the monitor automaton and return metadata. *)
val stage_monitor_generation_with_info :
  Stage_types.parsed ->
  Stage_types.parsed * monitor_generation_stage * Stage_info.monitor_generation_info

(* Add user contract coherency/compatibility constraints. *)
val stage_contracts :
  Stage_types.parsed * monitor_generation_stage ->
  Stage_types.contracts_stage * monitor_generation_stage

(* Add user contract coherency/compatibility constraints + metadata. *)
val stage_contracts_with_info :
  Stage_types.parsed * monitor_generation_stage ->
  Stage_types.contracts_stage * monitor_generation_stage * Stage_info.contracts_info

(* Inject monitor-related contracts into transitions. *)
val stage_monitor_injection :
  Stage_types.contracts_stage * monitor_generation_stage ->
  Stage_types.monitor_stage * monitor_generation_stage

(* Inject monitor-related contracts into transitions + metadata. *)
val stage_monitor_injection_with_info :
  Stage_types.contracts_stage * monitor_generation_stage ->
  Stage_types.monitor_stage * monitor_generation_stage * Stage_info.monitor_info

(* Compose all middle-end stages in order. *)
val run : Stage_types.parsed -> Stage_types.monitor_stage * monitor_generation_stage
