(** Provenance helpers for FO formulas. *)

val with_origin : ?loc:Ast.loc -> Ast.origin -> Ast.fo -> Ast.fo_o
val map_with_origin : (Ast.fo -> Ast.fo) -> Ast.fo_o -> Ast.fo_o
val values : Ast.fo_o list -> Ast.fo list
val origins : Ast.fo_o list -> Ast.origin option list
