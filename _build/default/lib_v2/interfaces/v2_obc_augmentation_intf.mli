(** Fine-grained families for formulas injected in augmented OBC. *)

type obc_formula_family =
  | FamTransitionRequires
  | FamTransitionEnsures
  | FamCoherencyRequires
  | FamCoherencyEnsuresShifted
  | FamInitialCoherencyGoal
  | FamNoBadRequires
  | FamNoBadEnsures
  | FamMonitorCompatibilityRequires
  | FamStateAwareAssumptionRequires

module type OBC_AUGMENTATION = sig
  type obligation

  val family_of : obligation -> obc_formula_family
end
