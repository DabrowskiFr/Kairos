(** Derive post-oriented invariant summaries from an abstract node. *)

type t = {
  inv_of_state : Ast.ident -> Ast.ltl option;
  inv_from_ensures : Ast.ident -> Ast.ltl option;
}

val build : Normalized_program.node -> t
