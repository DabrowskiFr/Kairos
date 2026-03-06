From Stdlib Require Import Logic.Classical.

Require Import core.CoreStepSig.
Require Import monitor.MonitorSig.
Require Import monitor.InputMonitor.
Require Import monitor.GuaranteeMonitor.
Require Import obligations.ObligationGenSig.
Require Import obligations.OracleSig.
Require Import obligations.OracleSemSig.

Set Implicit Arguments.

Module Type LOCAL_COVERAGE_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Parameter AvoidA : C.stream C.InputVal -> Prop.
  Parameter AvoidG : C.stream (C.InputVal * C.OutputVal) -> Prop.

  Parameter coverage_if_not_avoidG :
    forall u,
      AvoidA u ->
      ~ AvoidG (C.run_trace u) ->
      exists k (obl : E.Obligation), E.Generated obl /\ ~ obl (C.ctx_at u k).
End LOCAL_COVERAGE_SIG.

Module MakeSafetyKernel
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (O : ORACLE_SEM_SIG C E)
  (Cov : LOCAL_COVERAGE_SIG C E).

  Theorem oracle_conditional_correctness_modular :
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    intros u HA.
    destruct (classic (Cov.AvoidG (C.run_trace u))) as [HG | HnG].
    - exact HG.
    - destruct (@Cov.coverage_if_not_avoidG u HA HnG) as [k [obl [Hgen Hnot]]].
      pose proof (O.Oracle_complete (obl := obl) Hgen) as Hor.
      pose proof (O.Oracle_sound (obl := obl) Hor) as Hvalid.
      exfalso.
      apply Hnot.
      exact (O.obligation_valid_pointwise u k Hvalid).
  Qed.
End MakeSafetyKernel.
