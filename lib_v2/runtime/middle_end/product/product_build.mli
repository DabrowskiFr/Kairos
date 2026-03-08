type analysis = {
  exploration : Product_types.exploration;
  assume_bad_idx : int;
  guarantee_bad_idx : int;
  guarantee_state_labels : string list;
  assume_state_labels : string list;
}

val analyze_node :
  build:Automata_generation.automata_build ->
  node:Abstract_model.node ->
  analysis
