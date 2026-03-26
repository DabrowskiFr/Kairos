(** Structural queries and small utilities over the source AST. *)

(** Render a source location in a compact human-readable form. *)
val loc_to_string : Ast.loc -> string

(** Names of the input variables declared by a node. *)
val input_names_of_node : Ast.node -> Ast.ident list

(** Names of the output variables declared by a node. *)
val output_names_of_node : Ast.node -> Ast.ident list

(** Build an index from source state names to their outgoing transitions. *)
val transitions_from_state_fn : Ast.node -> Ast.ident -> Ast.transition list
