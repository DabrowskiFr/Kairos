Require Import core.CoreStepSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.ObligationTaxonomySig.
Require Import obligations.OracleSemSig.
Require Import kernels.ObjectiveSafetyKernel.

Set Implicit Arguments.

Module MakeSupportNonBlockingKernel
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (T : OBLIGATION_TAXONOMY_SIG E)
  (Cov : LOCAL_OBJECTIVE_COVERAGE_SIG C E T)
  (Oref : ORACLE_SEM_SIG C E)
  (Oalt : ORACLE_SEM_SIG C E).

  Module ObjAlt := MakeObjectiveSafetyKernel C E T Oalt Cov.

  Theorem correction_preserved_if_oracles_agree_on_objectives :
    (forall cl, T.GeneratedObjective cl -> Oref.Oracle cl = true) ->
    (forall cl, T.GeneratedObjective cl -> Oalt.Oracle cl = Oref.Oracle cl) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    intros HallRef Hagree u HA.
    apply ObjAlt.oracle_conditional_correctness_from_objectives.
    intros cl Hobj.
    rewrite Hagree; [|exact Hobj].
    apply HallRef.
    exact Hobj.
    exact HA.
  Qed.

  Theorem correction_preserved_if_oracles_agree_on_objectives_and_coherency :
    (forall cl, T.GeneratedObjective cl -> Oref.Oracle cl = true) ->
    (forall cl, T.GeneratedInitialGoal cl -> Oref.Oracle cl = true) ->
    (forall cl, T.GeneratedUserInvariant cl -> Oref.Oracle cl = true) ->
    (forall cl, T.GeneratedObjective cl -> Oalt.Oracle cl = Oref.Oracle cl) ->
    (forall cl, T.GeneratedInitialGoal cl -> Oalt.Oracle cl = Oref.Oracle cl) ->
    (forall cl, T.GeneratedUserInvariant cl -> Oalt.Oracle cl = Oref.Oracle cl) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u)
      /\
      (forall k (cl : E.Clause),
         T.GeneratedUserInvariant cl ->
         cl (C.ctx_at u k)).
  Proof.
    intros HallRefObj HallRefInit HallRefUser HagreeObj HagreeInit HagreeUser u HA.
    apply ObjAlt.oracle_conditional_correctness_with_supports.
    - intros cl Hobj.
      rewrite HagreeObj; [|exact Hobj].
      apply HallRefObj.
      exact Hobj.
    - intros cl Hinit.
      rewrite HagreeInit; [|exact Hinit].
      apply HallRefInit.
      exact Hinit.
    - intros cl Huser.
      rewrite HagreeUser; [|exact Huser].
      apply HallRefUser.
      exact Huser.
    - exact HA.
  Qed.
End MakeSupportNonBlockingKernel.
