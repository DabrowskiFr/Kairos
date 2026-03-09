From Kairos.monitor Require Import MonitorSig.
From Kairos.monitor Require Import InputMonitor.
From Kairos.logic Require Import FOLanguageSig.

Set Implicit Arguments.

Module Type SHIFT_SPEC_SIG
  (A : MONITOR_SIG)
  (I : INPUT_ADMISSIBILITY_SIG A)
  (L : FO_LOGIC_SIG with Definition InputVal := A.Obs).

  Axiom shift_fo_correct_if_input_ok :
    forall d u k phi,
      I.InputOk u k ->
      L.eval_fo (L.ctx_at u k) (L.shift_fo d phi) <->
      L.eval_fo (L.ctx_at u (k + d)) phi.
End SHIFT_SPEC_SIG.
