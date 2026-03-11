(* Middle‑end stage combinators (automata generation -> instrumentation -> contracts). *)

(* Run automata generation without extra metadata. *)
val stage_automata_generation :
  Stage_types.parsed -> Stage_types.parsed * Middle_end_stages.automata_stage

(* Run automata generation and collect stage metadata. *)
val stage_automata_generation_with_info :
  Stage_types.parsed ->
  Stage_types.parsed
  * Middle_end_stages.automata_stage
  * Stage_info.automata_info

(* Run the contracts pass (user contract coherency). *)
val stage_contracts :
  Stage_types.instrumentation_stage * Middle_end_stages.automata_stage ->
  Stage_types.contracts_stage * Middle_end_stages.automata_stage

(* Run the contracts pass and collect metadata. *)
val stage_contracts_with_info :
  Stage_types.instrumentation_stage * Middle_end_stages.automata_stage ->
  Stage_types.contracts_stage
  * Middle_end_stages.automata_stage
  * Stage_info.contracts_info

(* Run instrumentation pass (inject code, then add no-bad-state and compatibility obligations). *)
val stage_instrumentation :
  ?external_summaries:Product_kernel_ir.exported_node_summary_ir list ->
  Stage_types.parsed * Middle_end_stages.automata_stage ->
  Stage_types.instrumentation_stage * Middle_end_stages.automata_stage

(* Run instrumentation and collect metadata. *)
val stage_instrumentation_with_info :
  ?external_summaries:Product_kernel_ir.exported_node_summary_ir list ->
  Stage_types.parsed * Middle_end_stages.automata_stage ->
  Stage_types.instrumentation_stage * Middle_end_stages.automata_stage * Stage_info.instrumentation_info

(* Compose all middle‑end stages in order. *)
val run :
  Stage_types.parsed -> Stage_types.contracts_stage * Middle_end_stages.automata_stage
