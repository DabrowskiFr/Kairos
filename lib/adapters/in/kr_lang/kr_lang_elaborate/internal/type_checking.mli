(** Static type checking for already lowered executable and historical expressions. *)

val check_expected_type : context:string -> Kr_lang_core.Kr_lang_core_syntax.ty -> Kr_lang_core.Kr_lang_core_syntax.ty -> unit
(** Check type compatibility in a named diagnostic context. *)

val infer_expr_type : Env.env -> Kr_lang_core.Kr_lang_core_syntax.expr -> Kr_lang_core.Kr_lang_core_syntax.ty
(** Infer the type of an executable Core expression. *)

val infer_hexpr_type : Env.env -> Kr_lang_core.Kr_lang_core_syntax.hexpr -> Kr_lang_core.Kr_lang_core_syntax.ty
(** Infer the type of a historical Core expression. *)
