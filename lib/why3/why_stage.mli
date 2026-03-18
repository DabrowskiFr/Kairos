(* Why3 stage helpers (AST → Why3 AST → text). *)

(* Render a Why3 AST to text. *)
val emit_ast : Emit.program_ast -> string
