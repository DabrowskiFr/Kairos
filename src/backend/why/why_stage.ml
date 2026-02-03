module A = Ast

let build_ast ?(prefix_fields=true) (p:A.program) : Emit.program_ast =
  let comment_map =
    List.map
      (fun (n:A.node) -> (n.nname, (n.assumes, n.guarantees, n.trans, [])))
      p
  in
  Why_contracts.set_pure_translation true;
  let ast = Emit.compile_program_ast ~prefix_fields ~comment_map p in
  Why_contracts.set_pure_translation false;
  ast

let emit_ast (ast:Emit.program_ast) : string =
  Why_emit.emit_program_ast ast

let compile_program ?(prefix_fields=true) (p:A.program) : string =
  p |> build_ast ~prefix_fields |> emit_ast
