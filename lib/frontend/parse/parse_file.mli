(** File-based parsing helpers built on top of the lexer and parser. *)

(** Parse one source file into the import-aware representation and collect
    parse metadata. *)
val parse_source_file_with_info : string -> Source_file.t * Stage_info.parse_info

(** Parse one source file and discard explicit imports, keeping only the node
    program. *)
val parse_file : string -> Ast.program

(** Parse one source file into an [Ast.program] together with parse metadata. *)
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
