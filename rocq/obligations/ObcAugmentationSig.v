Require Import obligations.ObligationGenSig.
Require Import obligations.ObligationTaxonomySig.

Set Implicit Arguments.

(* Fine-grained abstraction of formulas injected in the augmented OBC layer
   (before external VC generation). *)
Inductive obc_formula_family : Type :=
| FamTransitionRequires
| FamTransitionEnsures
| FamCoherencyRequires
| FamCoherencyEnsuresShifted
| FamInitialCoherencyGoal
| FamNoBadRequires
| FamNoBadEnsures
| FamMonitorCompatibilityRequires
| FamStateAwareAssumptionRequires.

Module Type OBC_AUGMENTATION_SIG
  (E : OBLIGATION_GEN_SIG)
  (T : OBLIGATION_TAXONOMY_SIG E).

  Parameter family_of : E.Obligation -> obc_formula_family.

  Definition GeneratedFamily (f : obc_formula_family) (obl : E.Obligation) : Prop :=
    E.Generated obl /\ family_of obl = f.

  (* Every generated obligation in the augmented OBC belongs to one of the
     explicit formula families above. *)
  Axiom generated_has_family :
    forall obl, E.Generated obl -> GeneratedFamily (family_of obl) obl.

  (* Compatibility links with the coarse taxonomy used by the kernels. *)
  Axiom no_bad_families_are_objective :
    forall obl,
      GeneratedFamily FamNoBadRequires obl \/ GeneratedFamily FamNoBadEnsures obl ->
      T.GeneratedObjective obl.

  Axiom coherency_families_are_coherency :
    forall obl,
      GeneratedFamily FamCoherencyRequires obl
      \/ GeneratedFamily FamCoherencyEnsuresShifted obl
      \/ GeneratedFamily FamInitialCoherencyGoal obl ->
      T.GeneratedCoherency obl.

  Axiom support_automaton_families_are_support :
    forall obl,
      GeneratedFamily FamMonitorCompatibilityRequires obl
      \/ GeneratedFamily FamStateAwareAssumptionRequires obl ->
      T.GeneratedSupportAutomaton obl.

  Axiom transition_contract_families_are_generated :
    forall obl,
      GeneratedFamily FamTransitionRequires obl
      \/ GeneratedFamily FamTransitionEnsures obl ->
      E.Generated obl.
End OBC_AUGMENTATION_SIG.
