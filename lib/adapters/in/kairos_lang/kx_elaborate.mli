(** Main surface-to-core elaboration pass.

    It validates surface-only constructs, expands indexed declarations and
    finite loops or quantifiers, orders observers, introduces required private
    ghosts, infers method effects, and lowers nodes to [Kx_core_ast]. Parsing and the
    later translation to [Verification_model] are outside this module. *)

type source = {
  imports : Kx_surface_ast.import_decl list;
      (** Imports retained for parsing-layer resolution and reporting. *)
  type_decls : Kx_core_syntax.enum_decl list;
      (** Elaborated global enum declarations. *)
  function_decls : Kx_core_syntax.pure_function_decl list;
      (** Elaborated global pure functions. *)
  nodes : Kx_core_ast.program; (** Elaborated program nodes. *)
}
(** Complete result of elaborating one parsed source file. *)

val elaborate_source : Kx_surface_ast.source -> source
(** Validate and elaborate a complete surface source. Raises a classified
    frontend error when a surface construct cannot be lowered. *)
