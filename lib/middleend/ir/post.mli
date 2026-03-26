(** Compute and materialize postconditions on normalized transitions. *)

type t = { product_transitions : Ir.product_contract list }

val build :
  node:Ir.node ->
  analysis:Product_build.analysis ->
  t

val apply :
  post_generation:t ->
  Ir.node ->
  Ir.node

val build_program :
  analyses:(Ast.ident * Product_build.analysis) list ->
  Ir.node list ->
  (Ast.ident * t) list

val apply_program :
  post_generations:(Ast.ident * t) list ->
  Ir.node list ->
  Ir.node list
