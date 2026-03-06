From Stdlib Require Import Logic.Classical.

Require Import core.CoreStepSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.ObligationTaxonomySig.
Require Import obligations.OracleSemSig.

Set Implicit Arguments.

Module Type LOCAL_OBJECTIVE_COVERAGE_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (T : OBLIGATION_TAXONOMY_SIG E).

  Parameter AvoidA : C.stream C.InputVal -> Prop.
  Parameter AvoidG : C.stream (C.InputVal * C.OutputVal) -> Prop.

  Parameter objective_coverage_if_not_avoidG :
    forall u,
      AvoidA u ->
      ~ AvoidG (C.run_trace u) ->
      exists k (obl : E.Obligation), T.GeneratedObjective obl /\ ~ obl (C.ctx_at u k).
End LOCAL_OBJECTIVE_COVERAGE_SIG.

Module MakeObjectiveSafetyKernel
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (T : OBLIGATION_TAXONOMY_SIG E)
  (O : ORACLE_SEM_SIG C E)
  (Cov : LOCAL_OBJECTIVE_COVERAGE_SIG C E T).

  Theorem coherency_obligations_hold_pointwise :
    (forall obl, T.GeneratedCoherency obl -> O.Oracle obl = true) ->
    forall u k (obl : E.Obligation),
      T.GeneratedCoherency obl ->
      obl (C.ctx_at u k).
  Proof.
    intros HallCoh u k obl Hcoh.
    pose proof (HallCoh obl Hcoh) as Hor.
    pose proof (O.Oracle_sound (obl := obl) Hor) as Hvalid.
    exact (O.obligation_valid_pointwise u k Hvalid).
  Qed.

  Theorem oracle_conditional_correctness_from_objectives :
    (forall obl, T.GeneratedObjective obl -> O.Oracle obl = true) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    intros HallObj u HA.
    destruct (classic (Cov.AvoidG (C.run_trace u))) as [HG | HnG].
    - exact HG.
    - destruct (@Cov.objective_coverage_if_not_avoidG u HA HnG) as [k [obl [Hobj Hnot]]].
      pose proof (HallObj obl Hobj) as Hor.
      pose proof (O.Oracle_sound (obl := obl) Hor) as Hvalid.
      exfalso.
      apply Hnot.
      exact (O.obligation_valid_pointwise u k Hvalid).
  Qed.

  Theorem oracle_conditional_correctness_with_coherency :
    (forall obl, T.GeneratedObjective obl -> O.Oracle obl = true) ->
    (forall obl, T.GeneratedCoherency obl -> O.Oracle obl = true) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u)
      /\
      (forall k (obl : E.Obligation),
         T.GeneratedCoherency obl ->
         obl (C.ctx_at u k)).
  Proof.
    intros HallObj HallCoh u HA.
    split.
    - apply oracle_conditional_correctness_from_objectives; assumption.
    - intros k obl Hcoh.
      eapply coherency_obligations_hold_pointwise.
      + exact HallCoh.
      + exact Hcoh.
  Qed.
End MakeObjectiveSafetyKernel.
