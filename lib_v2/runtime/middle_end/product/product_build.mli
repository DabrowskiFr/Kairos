type analysis = {
  exploration : Product_types.exploration;
  guarantee_state_labels : string list;
  assume_state_labels : string list;
}

val analyze_node :
  build:Automata_generation.automata_build ->
  node:Abstract_model.node ->
  analysis
