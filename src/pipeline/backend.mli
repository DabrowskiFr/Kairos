(* Backend entry points for Why3/DOT emission. *)

(* Render a Why3 AST to textual Why3. *)
val emit_why_ast : Emit.program_ast -> string

(* Render DOT monitor graph and labels (dot_text, labels_text). *)
val emit_dot : show_labels:bool -> Ast.program -> string * string
