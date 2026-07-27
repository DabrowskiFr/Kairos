(** Canonical formulas reused by distinct contracts. *)

type formula_id = int

type definition = {
  id : formula_id;
  formula : Core_syntax.history_free Ir.summary_formula;
}

type t

val build : Core_syntax.history_free Ir.summary_formula list list -> t
val definitions : t -> definition list
val find : t -> Core_syntax.history_free Ir.summary_formula -> definition option
(** Finds the shared definition assigned to this indexed formula occurrence.
    Structural equivalence is decided once by {!build}; subsequent lookups use
    the occurrence [oid]. *)
