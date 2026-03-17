val compat_invariants :
  node:Abstract_model.node ->
  analysis:Product_build.analysis ->
  Ast.invariant_state_rel list

val add_assumption_projection_requires :
  ?log:(Abstract_model.transition -> Ast.fo -> unit) option ->
  build:Automata_generation.automata_build ->
  analysis:Product_build.analysis ->
  Abstract_model.transition list ->
  Abstract_model.transition list

val add_bad_guarantee_projection_ensures :
  ?log:(Abstract_model.transition -> Ast.fo -> unit) option ->
  analysis:Product_build.analysis ->
  Abstract_model.transition list ->
  Abstract_model.transition list
