From Stdlib Require Import Arith.Arith.

Require Import core.CoreStepSig.
Require Import monitor.MonitorSig.
Require Import monitor.InputMonitor.
Require Import logic.FOLanguageSig.
Require Import logic.ShiftSpecSig.

Set Implicit Arguments.

Module MakeShiftKernel
  (C : CORE_STEP_SIG)
  (A : MONITOR_SIG with Definition Obs := C.InputVal)
  (I : INPUT_ADMISSIBILITY_SIG A)
  (L : FO_LOGIC_SIG
       with Definition InputVal := C.InputVal
       with Definition OutputVal := C.OutputVal
       with Definition StepCtx := C.StepCtx
       with Definition ctx_at := C.ctx_at)
  (Sh : SHIFT_SPEC_SIG A I L).

  Theorem shift_one_step_under_A :
    forall u k phi,
      I.AvoidA u ->
      L.eval_fo (C.ctx_at u k) (L.shift_fo 1 phi) ->
      L.eval_fo (C.ctx_at u (S k)) phi.
  Proof.
    intros u k phi HA Hshifted.
    pose proof (@I.avoid_implies_input_ok u k HA) as Hok.
    pose proof (@Sh.shift_fo_correct_if_input_ok 1 u k phi Hok) as Heq.
    rewrite Nat.add_1_r in Heq.
    exact ((proj1 Heq) Hshifted).
  Qed.
End MakeShiftKernel.
