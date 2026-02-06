val string_of_program : Ast_obc.program -> string
val compile_program : Ast_obc.program -> string
val compile_program_with_spans :
  Ast_obc.program -> string * (int * (int * int)) list
