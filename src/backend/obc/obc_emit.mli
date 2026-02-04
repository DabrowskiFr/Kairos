val string_of_program : Ast.program -> string
val compile_program : Ast.program -> string
val compile_program_with_spans :
  Ast.program -> string * (int * (int * int)) list
