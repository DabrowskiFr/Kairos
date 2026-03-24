(** Provenance helpers for annotated formulas.

    These helpers attach and rewrite the [origin] metadata used for VC tracing. *)

(* Wrap a FO formula with origin + optional location, allocating a fresh id. *)
val with_origin : ?loc:Ast.loc -> Formula_origin.t -> Ast.ltl -> Ast.ltl_o

(* Map the underlying FO formula while preserving origin/id/loc. *)
val map_with_origin : (Ast.ltl -> Ast.ltl) -> Ast.ltl_o -> Ast.ltl_o

(* Extract raw FO formulas from a list of annotated formulas. *)
val values : Ast.ltl_o list -> Ast.ltl list

(* Extract origin tags from a list of annotated formulas. *)
val origins : Ast.ltl_o list -> Formula_origin.t option list
