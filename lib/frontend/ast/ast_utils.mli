(** Small utilities for AST-related types, names, and locations. *)

(* Render an origin as a stable, human‑readable string. *)
val origin_to_string : Ast.origin -> string

(* Parse a string back into an origin (if recognized). *)
val origin_of_string : string -> Ast.origin option

(* Pretty print a location as "line:col-line_end:col_end". *)
val loc_to_string : Ast.loc -> string

(* Total ordering for locations (useful for sorting). *)
val compare_loc : Ast.loc -> Ast.loc -> int

(* Predicate telling whether an identifier is one of the node inputs. *)
val is_input_of_node : Ast.node -> Ast.ident -> bool

(* Input variable names in declaration order. *)
val input_names_of_node : Ast.node -> Ast.ident list

(* Output variable names in declaration order. *)
val output_names_of_node : Ast.node -> Ast.ident list

(* Build an efficient transition lookup function by source state. *)
val transitions_from_state_fn : Ast.node -> Ast.ident -> Ast.transition list

(* Build an efficient require lookup function by source state. *)
val requires_from_state_fn : Ast.node -> Ast.ident -> Ast.ltl list

(* Add (deduplicated) coherency goals to [node.attrs.coherency_goals]. *)
val add_new_coherency_goals : Ast.node -> Ast.ltl list -> Ast.node

(* Debug string representation of a program (mainly for dumps). *)
val show_program : Ast.program -> string
