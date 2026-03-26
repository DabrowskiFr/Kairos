(** Public parsing entry points for the frontend. *)

(** Parse a file and keep the explicit import declarations alongside the node
    program. *)
val parse_source_file_with_info : string -> Source_file.t * Stage_info.parse_info

(** Parse a file and return only the node program. *)
val parse_file : string -> Ast.program

(** Same as {!parse_file}, but also return frontend parse metadata. *)
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
