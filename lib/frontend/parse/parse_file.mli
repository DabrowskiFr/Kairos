(** File-level parser entry points built on top of the lexer/parser. *)

val parse_source_file : string -> Source_file.t
val parse_source_file_with_info : string -> Source_file.t * Stage_info.parse_info
val parse_file : string -> Ast.program
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
