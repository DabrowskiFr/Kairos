(** Build normalized nodes directly from source AST nodes. *)

val of_ast_transition : Ast.transition -> Ir.transition

val of_ast_contract_formula :
  ?origin:Formula_origin.t ->
  Ast.ltl_o ->
  Ir.contract_formula

val of_ast_node : Ast.node -> Ir.node

val of_ast_program : Ast.program -> Ir.node list
