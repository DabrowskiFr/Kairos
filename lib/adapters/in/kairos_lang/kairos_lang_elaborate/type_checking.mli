(** Static type checking for already lowered executable and historical expressions. *)

val check_expected_type : context:string -> Core.Syntax.ty -> Core.Syntax.ty -> unit
(** Check type compatibility in a named diagnostic context. *)

val infer_expr_type : Env.env -> Core.Syntax.expr -> Core.Syntax.ty
(** Infer the type of an executable Core expression. *)

val infer_hexpr_type : Env.env -> Core.Syntax.hexpr -> Core.Syntax.ty
(** Infer the type of a historical Core expression. *)
