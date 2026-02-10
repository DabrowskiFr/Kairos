(** Why3 stage helpers (AST → Why3 AST → text). *)

(** Build the Why3 AST from the OBC AST. *)
val build_ast : ?prefix_fields:bool -> Ast.program -> Emit.program_ast
(** Render a Why3 AST to text. *)
val emit_ast : Emit.program_ast -> string
(** Convenience: compile program to Why3 text. *)
val compile_program : ?prefix_fields:bool -> Ast.program -> string
