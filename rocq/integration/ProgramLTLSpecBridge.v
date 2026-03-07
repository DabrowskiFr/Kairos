Require Import integration.ThreeLayerArchitecture.
Require Import logic.LTLPredicate.

Set Implicit Arguments.

Module Type PROGRAM_LTL_SPEC_SIG
  (P : PROGRAM_LAYER_SIG)
  (L : LTL_PREDICATE_SIG with Definition Obs := (P.InputVal * P.OutputVal)%type).

  Parameter phiG : L.Formula.

  Axiom avoidG_characterizes_phiG :
    forall w,
      P.AvoidG w <-> L.sat phiG w.
End PROGRAM_LTL_SPEC_SIG.

Module MakeProgramLTLCorrectness
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_LAYER_SIG P)
  (S : VALIDATION_LAYER_SIG P K)
  (L : LTL_PREDICATE_SIG with Definition Obs := (P.InputVal * P.OutputVal)%type)
  (Spec : PROGRAM_LTL_SPEC_SIG P L).

  Module Corr := MakeThreeLayerCorrectness P K S.

  Theorem program_satisfies_ltl_under_A :
    forall u,
      P.AvoidA u ->
      L.sat Spec.phiG (P.run_trace u).
  Proof.
    intros u HA.
    apply (proj1 (Spec.avoidG_characterizes_phiG (P.run_trace u))).
    apply Corr.validation_conditional_correctness_three_layers.
    exact HA.
  Qed.
End MakeProgramLTLCorrectness.
