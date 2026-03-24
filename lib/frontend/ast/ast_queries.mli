(** Structural queries and small utilities over the source AST. *)

val loc_to_string : Ast.loc -> string
val compare_loc : Ast.loc -> Ast.loc -> int
val is_input_of_node : Ast.node -> Ast.ident -> bool
val input_names_of_node : Ast.node -> Ast.ident list
val output_names_of_node : Ast.node -> Ast.ident list
val transitions_from_state_fn : Ast.node -> Ast.ident -> Ast.transition list
