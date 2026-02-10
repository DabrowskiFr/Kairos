(** Small utilities for AST-related types. *)

(** Render an origin as a stable, human‑readable string. *)
val origin_to_string : Ast.origin -> string
(** Parse a string back into an origin (if recognized). *)
val origin_of_string : string -> Ast.origin option

(** Pretty print a location as "line:col-line_end:col_end". *)
val loc_to_string : Ast.loc -> string
(** Total ordering for locations (useful for sorting). *)
val compare_loc : Ast.loc -> Ast.loc -> int

(** Debug string representation of a program (mainly for dumps). *)
val show_program : Ast.program -> string
