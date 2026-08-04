(** Lower executable node structure from Surface AST to Core AST. *)

val lower_node : Env.env -> Surface.Ast.node -> Core.Ast.node
(** Validate and lower one complete node, including methods, transitions,
    contracts, observers, delays, and inferred effects. *)

val lower_function_decl : Env.env -> Surface.Ast.function_decl -> Core.Syntax.pure_function_decl
(** Lower one pure function and its first-order contracts. *)
