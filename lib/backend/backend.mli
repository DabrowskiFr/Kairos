(** Backend entry points for Why3/OBC/DOT emission. *)

(** Build the Why3 AST (Ptree) from the OBC AST. *)
val build_why_ast : prefix_fields:bool -> Ast.program -> Emit.program_ast
(** Render a Why3 AST to textual Why3. *)
val emit_why_ast : Emit.program_ast -> string
(** Render OBC+ textual output from the AST. *)
val emit_obc : Ast.program -> string
(** Render DOT monitor graph and labels (dot_text, labels_text). *)
val emit_dot : show_labels:bool -> Ast.program -> string * string
