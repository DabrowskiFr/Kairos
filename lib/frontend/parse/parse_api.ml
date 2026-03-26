let parse_source_file_with_info : string -> Source_file.t * Stage_info.parse_info =
  Parse_file.parse_source_file_with_info

let parse_file : string -> Ast.program = Parse_file.parse_file

let parse_file_with_info : string -> Ast.program * Stage_info.parse_info =
  Parse_file.parse_file_with_info
