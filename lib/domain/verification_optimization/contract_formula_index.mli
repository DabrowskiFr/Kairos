(** Canonical formulas reused by distinct contracts. *)

type formula_id = int

type definition = {
  id : formula_id;
  formula : Core_syntax.history_free Ir.summary_formula;
  occurrence_ids : Ir_shared_types.formula_id list;
}

val build :
  Core_syntax.history_free Ir.summary_formula list list ->
  definition list
