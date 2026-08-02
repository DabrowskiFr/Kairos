(** Main surface-to-core elaboration pass.

    It validates surface-only constructs, expands indexed declarations and
    finite loops or quantifiers, orders observers, introduces required private
    ghosts, infers method effects, and lowers nodes to [Core.Ast]. Parsing and the
    later translation to [Verification_model] are outside this module. *)

type source = {
  type_decls : Core.Syntax.enum_decl list;
      (** Elaborated global enum declarations. *)
  function_decls : Core.Syntax.pure_function_decl list;
      (** Elaborated global pure functions. *)
  nodes : Core.Ast.program; (** Elaborated program nodes. *)
}
(** Complete result of elaborating one parsed source file. *)

val elaborate_source : Surface.Ast.source -> source
(** Validate and elaborate a complete surface source. Raises a classified
    frontend error when a surface construct cannot be lowered. *)
