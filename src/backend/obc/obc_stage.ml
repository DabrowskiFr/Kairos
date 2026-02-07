open Ast

let run (p:Ast.program) : Ast.program =
  List.map Obc_ghost_instrument.transform_node_ghost p
