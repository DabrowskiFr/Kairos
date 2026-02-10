(* Frontend entry points (parsing + AST dumps). *)

(** Parse an input file into the AST (raises on error). *)
val parse_file : string -> Ast.program
(** Parse an input file and return parse metadata. *)
val parse_file_with_info : string -> Ast.program * Stage_info.parse_info
(** Dump AST as JSON (mainly for debugging). *)
val dump_program_json : out:string option -> Ast.program -> unit
(** Dump AST as JSON with stable ordering (deterministic output). *)
val dump_program_json_stable :
  out:string option -> Ast.program -> unit
