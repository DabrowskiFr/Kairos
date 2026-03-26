(** Builds post-instrumentation IR artifacts and metadata from an already
    instrumented abstract node. *)

val build_instrumentation_info :
  build:Automaton_types.automata_build ->
  ?nodes:Ir.node list ->
  Ir.node ->
  Stage_info.instrumentation_info
