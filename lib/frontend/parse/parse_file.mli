(** Low-level parser entry points. *)

(** Parse an input file into the AST (raises on error). *)
val parse_file : string -> Ast.program
(** Parse an input file and return parse metadata. *)
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
