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
      exists k (cl : E.Clause), T.GeneratedObjective cl /\ ~ cl (C.ctx_at u k).
End LOCAL_OBJECTIVE_COVERAGE_SIG.

Module MakeObjectiveSafetyKernel
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (T : OBLIGATION_TAXONOMY_SIG E)
  (O : ORACLE_SEM_SIG C E)
  (Cov : LOCAL_OBJECTIVE_COVERAGE_SIG C E T).

  Theorem user_invariant_obligations_hold_pointwise :
    (forall cl, T.GeneratedUserInvariant cl -> O.Oracle cl = true) ->
    forall u k (cl : E.Clause),
      T.GeneratedUserInvariant cl ->
      cl (C.ctx_at u k).
  Proof.
    intros HallUser u k cl Huser.
    pose proof (HallUser cl Huser) as Hor.
    pose proof (O.Oracle_sound (cl := cl) Hor) as Hvalid.
    exact (O.clause_valid_pointwise u k Hvalid).
  Qed.

  Theorem initial_goals_hold_at_tick0 :
    (forall cl, T.GeneratedInitialGoal cl -> O.Oracle cl = true) ->
    forall u (cl : E.Clause),
      T.GeneratedInitialGoal cl ->
      cl (C.ctx_at u 0).
  Proof.
    intros HallInit u cl Hinit.
    pose proof (HallInit cl Hinit) as Hor.
    pose proof (O.Oracle_sound (cl := cl) Hor) as Hvalid.
    exact (O.clause_valid_pointwise u 0 Hvalid).
  Qed.

  Theorem validation_conditional_correctness_from_objectives :
    (forall cl, T.GeneratedObjective cl -> O.Oracle cl = true) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    intros HallObj u HA.
    destruct (classic (Cov.AvoidG (C.run_trace u))) as [HG | HnG].
    - exact HG.
    - destruct (@Cov.objective_coverage_if_not_avoidG u HA HnG) as [k [cl [Hobj Hnot]]].
      pose proof (HallObj cl Hobj) as Hor.
      pose proof (O.Oracle_sound (cl := cl) Hor) as Hvalid.
      exfalso.
      apply Hnot.
      exact (O.clause_valid_pointwise u k Hvalid).
  Qed.

  Theorem validation_conditional_correctness_with_supports :
    (forall cl, T.GeneratedObjective cl -> O.Oracle cl = true) ->
    (forall cl, T.GeneratedInitialGoal cl -> O.Oracle cl = true) ->
    (forall cl, T.GeneratedUserInvariant cl -> O.Oracle cl = true) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u)
      /\
      (forall k (cl : E.Clause),
         T.GeneratedUserInvariant cl ->
         cl (C.ctx_at u k)).
  Proof.
    intros HallObj _HallInit HallUser u HA.
    split.
    - apply validation_conditional_correctness_from_objectives; assumption.
    - intros k cl Huser.
      eapply user_invariant_obligations_hold_pointwise.
      + exact HallUser.
      + exact Huser.
  Qed.

  Theorem oracle_conditional_correctness_from_objectives :
    (forall cl, T.GeneratedObjective cl -> O.Oracle cl = true) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    exact validation_conditional_correctness_from_objectives.
  Qed.

  Theorem oracle_conditional_correctness_with_supports :
    (forall cl, T.GeneratedObjective cl -> O.Oracle cl = true) ->
    (forall cl, T.GeneratedInitialGoal cl -> O.Oracle cl = true) ->
    (forall cl, T.GeneratedUserInvariant cl -> O.Oracle cl = true) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u)
      /\
      (forall k (cl : E.Clause),
         T.GeneratedUserInvariant cl ->
         cl (C.ctx_at u k)).
  Proof.
    exact validation_conditional_correctness_with_supports.
  Qed.
End MakeObjectiveSafetyKernel.
