(** Provenance helpers for annotated formulas.

    These helpers attach and rewrite the [origin] metadata used for VC tracing. *)

(** Wrap a formula with origin and optional source location, allocating a fresh
    identifier. *)
val with_origin : ?loc:Ast.loc -> Formula_origin.t -> Ast.ltl -> Ast.ltl_o
