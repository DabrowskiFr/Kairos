(** OBC+ stage wrapper around ghost/normalization passes. *)

(** Run OBC+ instrumentation. *)
val run : Ast.program -> Ast.program
(** Run OBC+ instrumentation and return metadata. *)
val run_with_info : Ast.program -> Ast.program * Stage_info.obc_info
