val parse_file : string -> Ast_user.program
val dump_program_json : out:string option -> Ast_user.program -> unit
val dump_program_json_stable :
  ?include_attrs:bool -> out:string option -> Ast_user.program -> unit
