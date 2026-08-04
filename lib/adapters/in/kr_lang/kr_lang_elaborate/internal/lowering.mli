(** Lower executable node structure from Surface AST to Core AST. *)

val lower_node : Env.env -> Kr_lang_surface.Kr_lang_surface_ast.node -> Kr_lang_core.Kr_lang_core_ast.node
(** Validate and lower one complete node, including methods, transitions,
    contracts, observers, delays, and inferred effects. *)

val lower_function_decl : Env.env -> Kr_lang_surface.Kr_lang_surface_ast.function_decl -> Kr_lang_core.Kr_lang_core_syntax.pure_function_decl
(** Lower one pure function and its first-order contracts. *)
