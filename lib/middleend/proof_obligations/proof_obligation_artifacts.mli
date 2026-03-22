(** Builds post-instrumentation IR artifacts and metadata from an already
    instrumented abstract node. *)

val build_instrumentation_info :
  build:Automata_generation.automata_build ->
  states:Ast.ltl list ->
  atom_names:Ast.ident list ->
  ?nodes:Normalized_program.node list ->
  ?external_summaries:Proof_kernel_ir.exported_node_summary_ir list ->
  Normalized_program.node ->
  Stage_info.instrumentation_info
