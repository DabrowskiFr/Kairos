(** Materialize invariant obligations on normalized transitions. *)

val invariant_of_state :
  Ir.node ->
  Ast.ident ->
  Ast.ltl option

type t = {
  invariant_of_state : Ast.ident -> Ast.ltl option;
}

val build :
  node:Ir.node ->
  t

val apply :
  invariant_generation:t ->
  Ir.node ->
  Ir.node

val build_program :
  Ir.node list ->
  (Ast.ident * t) list

val apply_program :
  invariant_generations:(Ast.ident * t) list ->
  Ir.node list ->
  Ir.node list
