let build_why_ast ~prefix_fields (p:Ast.program) : Emit.program_ast =
  Why_stage.build_ast ~prefix_fields p

let emit_why_ast (ast:Emit.program_ast) : string =
  Why_stage.emit_ast ast

let emit_obc (p:Ast.program) : string =
  Obc_emit.compile_program p

let emit_dot ~(show_labels:bool) (p:Ast.program) : string * string =
  Dot_emit.dot_monitor_program ~show_labels p
