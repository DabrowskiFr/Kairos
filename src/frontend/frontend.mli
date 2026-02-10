val parse_file : string -> Ast.program
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
val dump_program_json : out:string option -> Ast.program -> unit
val dump_program_json_stable :
  out:string option -> Ast.program -> unit
