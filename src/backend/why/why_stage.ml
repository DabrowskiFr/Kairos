module A = Ast

let build_ast ?(prefix_fields=true) (p:Ast_obc.program) : Emit.program_ast =
  let comment_map =
    List.map
      (fun (n:A.node) ->
         let trans = List.map Ast_obc.transition_of_ast (Ast.node_trans n) in
         ((Ast.node_sig n).nname,
          (Ast.node_assumes n, Ast.node_guarantees n, trans, [])))
      (Ast_obc.to_ast p)
  in
  Why_contracts.set_pure_translation true;
  let ast = Emit.compile_program_ast ~prefix_fields ~comment_map p in
  Why_contracts.set_pure_translation false;
  ast

let emit_ast (ast:Emit.program_ast) : string =
  Why_emit.emit_program_ast ast

let compile_program ?(prefix_fields=true) (p:Ast_obc.program) : string =
  p |> build_ast ~prefix_fields |> emit_ast
