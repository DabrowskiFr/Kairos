(* Middle‑end stage combinators (monitor generation → monitor pass → contracts). *)

(* Run monitor generation (automata) without extra metadata. *)
val stage_monitor_generation :
  Stage_types.parsed -> Stage_types.parsed * Middle_end_stages.monitor_generation_stage

(* Run monitor generation and collect stage metadata. *)
val stage_monitor_generation_with_info :
  Stage_types.parsed ->
  Stage_types.parsed
  * Middle_end_stages.monitor_generation_stage
  * Stage_info.monitor_generation_info

(* Run the contracts pass (user contract coherency). *)
val stage_contracts :
  Stage_types.monitor_stage * Middle_end_stages.monitor_generation_stage ->
  Stage_types.contracts_stage * Middle_end_stages.monitor_generation_stage

(* Run the contracts pass and collect metadata. *)
val stage_contracts_with_info :
  Stage_types.monitor_stage * Middle_end_stages.monitor_generation_stage ->
  Stage_types.contracts_stage
  * Middle_end_stages.monitor_generation_stage
  * Stage_info.contracts_info

(* Run monitor pass (instrument code, then add no-bad-state and compatibility obligations). *)
val stage_monitor_injection :
  Stage_types.parsed * Middle_end_stages.monitor_generation_stage ->
  Stage_types.monitor_stage * Middle_end_stages.monitor_generation_stage

(* Run monitor injection and collect metadata. *)
val stage_monitor_injection_with_info :
  Stage_types.parsed * Middle_end_stages.monitor_generation_stage ->
  Stage_types.monitor_stage * Middle_end_stages.monitor_generation_stage * Stage_info.monitor_info

(* Compose all middle‑end stages in order. *)
val run :
  Stage_types.parsed -> Stage_types.contracts_stage * Middle_end_stages.monitor_generation_stage
