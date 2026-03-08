From Stdlib Require Import Logic.Classical.

From Kairos.core Require Import CoreStepSig.
From Kairos.monitor Require Import MonitorSig.
From Kairos.monitor Require Import InputMonitor.
From Kairos.monitor Require Import GuaranteeMonitor.
From Kairos.obligations Require Import ObligationGenSig.
From Kairos.obligations Require Import OracleSig.
From Kairos.obligations Require Import OracleSemSig.

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
      exists k (cl : E.Clause), E.Generated cl /\ ~ cl (C.ctx_at u k).
End LOCAL_COVERAGE_SIG.

Module MakeSafetyKernel
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (O : ORACLE_SEM_SIG C E)
  (Cov : LOCAL_COVERAGE_SIG C E).

  Local Lemma validated_generated_clause_holds :
    forall u k (cl : E.Clause),
      E.Generated cl ->
      cl (C.ctx_at u k).
  Proof.
    intros u k cl Hgen.
    pose proof (O.Oracle_complete (cl := cl) Hgen) as Hor.
    pose proof (O.Oracle_sound (cl := cl) Hor) as Hvalid.
    exact (O.clause_valid_pointwise u k Hvalid).
  Qed.

  Theorem validation_conditional_correctness_modular :
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    intros u HA.
    destruct (classic (Cov.AvoidG (C.run_trace u))) as [HG | HnG].
    - exact HG.
    - destruct (@Cov.coverage_if_not_avoidG u HA HnG) as [k [cl [Hgen Hnot]]].
      exfalso.
      apply Hnot.
      exact (@validated_generated_clause_holds u k cl Hgen).
  Qed.

  Theorem oracle_conditional_correctness_modular :
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    exact validation_conditional_correctness_modular.
  Qed.
End MakeSafetyKernel.
