open Ast

let run (p:Ast_monitor.program) : Ast_obc.program =
  p
  |> Ast_monitor.to_ast
  |> List.map Ast_obc.node_of_ast
  |> List.map Obc_ghost_instrument.transform_node_ghost
  |> List.map Ast_obc.node_to_ast
  |> Ast_obc.of_ast
