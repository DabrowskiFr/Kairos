let emit_why_ast (ast : Emit.program_ast) : string = Why_stage.emit_ast ast

let emit_dot ~(show_labels : bool) (p : Ast.program) : string * string =
  Dot_emit.dot_monitor_program ~show_labels p
