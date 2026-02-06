val build_ast : ?prefix_fields:bool -> Ast_obc.program -> Emit.program_ast
val emit_ast : Emit.program_ast -> string
val compile_program : ?prefix_fields:bool -> Ast_obc.program -> string
