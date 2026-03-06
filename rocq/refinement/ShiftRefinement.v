Require Import refinement.RefinementSig.

Set Implicit Arguments.

Module Type CONCRETE_SHIFT_SIG.
  Parameter ConcrFO : Type.
  Parameter shift_concr : nat -> ConcrFO -> ConcrFO.
End CONCRETE_SHIFT_SIG.

Module Type ABSTRACT_SHIFT_SIG.
  Parameter AbsFO : Type.
  Parameter shift_abs : nat -> AbsFO -> AbsFO.
End ABSTRACT_SHIFT_SIG.

Module Type SHIFT_REFINEMENT_SIG
  (C : CONCRETE_SHIFT_SIG)
  (A : ABSTRACT_SHIFT_SIG)
  (R : REFINEMENT_SIG
     with Definition ConcrFO := C.ConcrFO
     with Definition AbsFO := A.AbsFO).

  Axiom shift_refines :
    forall d cfo afo,
      R.refines_fo cfo afo ->
      R.refines_fo (C.shift_concr d cfo) (A.shift_abs d afo).
End SHIFT_REFINEMENT_SIG.
