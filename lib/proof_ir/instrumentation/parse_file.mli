(** Low-level parser entry points used by the instrumentation and pipeline
    layers. *)

(* Parse an input file into a source file (imports + AST nodes). *)
val parse_source_file : string -> Source_file.t

(* Parse an input file into a source file and return parse metadata. *)
val parse_source_file_with_info : string -> Source_file.t * Stage_info.parse_info

(* Parse an input file into the AST (raises on error). *)
val parse_file : string -> Ast.program

(* Parse an input file and return parse metadata. *)
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
