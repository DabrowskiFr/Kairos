val build_why_ast : prefix_fields:bool -> Ast_obc.program -> Emit.program_ast
val emit_why_ast : Emit.program_ast -> string
val emit_obc : Ast_obc.program -> string
val emit_dot : show_labels:bool -> Ast_automaton.program -> string * string
