From Kairos.monitor Require Import MonitorSig.
From Kairos.logic Require Import LTLPredicate.

Set Implicit Arguments.

Module Type MONITOR_LTL_LINK_SIG
  (M : MONITOR_SIG)
  (L : LTL_PREDICATE_SIG with Definition Obs := M.Obs).

  Parameter phi : L.Formula.

  Axiom monitor_implements_phi :
    forall w,
      M.avoids_bad w <-> L.sat phi w.
End MONITOR_LTL_LINK_SIG.
