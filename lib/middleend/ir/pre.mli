(** Compute and materialize preconditions from transition postconditions. *)

type t = {
  guarantee_pre_of_product_state : Ir.product_state -> Ast.ltl option;
  initial_product_state : Ir.product_state;
  state_stability : Ast.ltl list;
}

val build :
  node:Ir.node ->
  analysis:Product_build.analysis ->
  t

val apply :
  pre_generation:t ->
  Ir.node ->
  Ir.node

val build_program :
  analyses:(Ast.ident * Product_build.analysis) list ->
  Ir.node list ->
  (Ast.ident * t) list

val apply_program :
  pre_generations:(Ast.ident * t) list ->
  Ir.node list ->
  Ir.node list
