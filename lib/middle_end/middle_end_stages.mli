(** Concrete middle-end stage modules wired into the main pipeline. *)

(* Automata generation stage implementation (swappable). *)
module Automata_generation :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.parsed
     and type stage_in = unit
     and type stage_out = Automata_pass_sig.stage
     and type info = Stage_info.automata_info

(* Contracts pass: adds user contract coherency constraints. *)
module Contracts :
  Middle_end_pass.S
    with type ast_in = Stage_types.instrumentation_stage
     and type ast_out = Stage_types.contracts_stage
     and type stage_in = Automata_pass_sig.stage
     and type stage_out = Automata_pass_sig.stage
     and type info = Stage_info.contracts_info

(* Instrumentation pass: instruments transitions using automata. *)
module Instrumentation :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.instrumentation_stage
     and type stage_in = Automata_pass_sig.stage
     and type stage_out = Automata_pass_sig.stage
     and type info = Stage_info.instrumentation_info

(* Stage artifact carrying per‑node automata. *)
type automata_stage = Automata_pass_sig.stage

(* Build the automata view (atoms -> automaton -> inline atoms). *)
val stage_automata_generation : Stage_types.parsed -> Stage_types.parsed * automata_stage

(* Build the automata view and return metadata. *)
val stage_automata_generation_with_info :
  Stage_types.parsed ->
  Stage_types.parsed * automata_stage * Stage_info.automata_info

(* Add user contract coherency constraints (after monitor instrumentation). *)
val stage_contracts :
  Stage_types.instrumentation_stage * automata_stage ->
  Stage_types.contracts_stage * automata_stage

(* Add user contract coherency constraints + metadata. *)
val stage_contracts_with_info :
  Stage_types.instrumentation_stage * automata_stage ->
  Stage_types.contracts_stage * automata_stage * Stage_info.contracts_info

(* Run instrumentation pass (code injection -> no-bad-state -> compatibility). *)
val stage_instrumentation :
  ?external_summaries:Product_kernel_ir.exported_node_summary_ir list ->
  Stage_types.parsed * automata_stage ->
  Stage_types.instrumentation_stage * automata_stage

(* Run instrumentation pass + metadata. *)
val stage_instrumentation_with_info :
  ?external_summaries:Product_kernel_ir.exported_node_summary_ir list ->
  Stage_types.parsed * automata_stage ->
  Stage_types.instrumentation_stage * automata_stage * Stage_info.instrumentation_info

(* Compose all middle-end stages in order: automata generation -> instrumentation -> contracts. *)
val run : Stage_types.parsed -> Stage_types.contracts_stage * automata_stage
