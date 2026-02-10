let parse_file : string -> Ast.program = Parse_file.parse_file
let parse_file_with_info : string -> Ast.program * Stage_info.parse_info =
  Parse_file.parse_file_with_info
let dump_program_json : out:string option -> Ast.program -> unit =
  Ast_dump.dump_program_json
let dump_program_json_stable ~(out:string option) (p:Ast.program) : unit =
  Ast_dump.dump_program_json_stable ~out p
