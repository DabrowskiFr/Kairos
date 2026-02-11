(* Provenance helpers for FO formulas. These helpers attach/rewrite the [origin] metadata used for
   VC tracing. *)

(* Wrap a FO formula with origin + optional location, allocating a fresh id. *)
val with_origin : ?loc:Ast.loc -> Ast.origin -> Ast.fo -> Ast.fo_o

(* Map the underlying FO formula while preserving origin/id/loc. *)
val map_with_origin : (Ast.fo -> Ast.fo) -> Ast.fo_o -> Ast.fo_o

(* Extract raw FO formulas from a list of annotated formulas. *)
val values : Ast.fo_o list -> Ast.fo list

(* Extract origin tags from a list of annotated formulas. *)
val origins : Ast.fo_o list -> Ast.origin option list
