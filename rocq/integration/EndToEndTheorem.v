Require Import core.CoreStepSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.OracleSig.
Require Import obligations.OracleSemSig.
Require Import kernels.SafetyKernel.

Set Implicit Arguments.

Module MakeEndToEnd
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (O : ORACLE_SEM_SIG C E)
  (Cov : LOCAL_COVERAGE_SIG C E).

  Module SK := MakeSafetyKernel C E O Cov.

  Theorem end_to_end_validation_conditional_correctness :
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    exact SK.validation_conditional_correctness_modular.
  Qed.

  Theorem end_to_end_oracle_conditional_correctness :
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    exact end_to_end_validation_conditional_correctness.
  Qed.
End MakeEndToEnd.
