(** Small utilities for AST-related types. *)

val origin_to_string : Ast.origin -> string
val origin_of_string : string -> Ast.origin option

val loc_to_string : Ast.loc -> string
val compare_loc : Ast.loc -> Ast.loc -> int

(** Debug string representation of a program (mainly for dumps). *)
val show_program : Ast.program -> string
