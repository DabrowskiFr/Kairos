(** Product exploration and analysis between program states and
    assume/guarantee automata. *)

type analysis = Product_analysis.analysis

val analyze_node :
  build:Automaton_types.automata_build ->
  node:Ir.node ->
  analysis
