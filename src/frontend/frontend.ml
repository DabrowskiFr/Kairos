let parse_file : string -> Ast.program = Parse_file.parse_file
let dump_program_json : out:string option -> Ast.program -> unit =
  Ast_dump.dump_program_json
let dump_program_json_stable ?include_attrs ~(out:string option) (p:Ast.program) : unit =
  Ast_dump.dump_program_json_stable ?include_attrs ~out p
