(** Canonical formulas reused by distinct contracts. *)

type formula_id = int

type definition = {
  id : formula_id;
  formula : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula;
  occurrence_ids : Kr_verification_ir_shared.formula_id list;
}

val build :
  Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list list ->
  definition list
