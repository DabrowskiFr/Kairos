(* OBC+ textual emission utilities. *)

(* Debug string representation of a program. *)
val string_of_program : Ast.program -> string

(* Render the AST to OBC+ text. *)
val compile_program : Ast.program -> string

(* Enable/disable debug comments carrying stable contract ids in OBC+ output. *)
val set_debug_contract_ids : bool -> unit

(* Render to OBC+ text and return spans per block. *)
val compile_program_with_spans : Ast.program -> string * (int * (int * int)) list
