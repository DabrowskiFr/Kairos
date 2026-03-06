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
    (forall obl, T.GeneratedObjective obl -> Oref.Oracle obl = true) ->
    (forall obl, T.GeneratedObjective obl -> Oalt.Oracle obl = Oref.Oracle obl) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u).
  Proof.
    intros HallRef Hagree u HA.
    apply ObjAlt.oracle_conditional_correctness_from_objectives.
    intros obl Hobj.
    rewrite Hagree; [|exact Hobj].
    apply HallRef.
    exact Hobj.
    exact HA.
  Qed.

  Theorem correction_preserved_if_oracles_agree_on_objectives_and_coherency :
    (forall obl, T.GeneratedObjective obl -> Oref.Oracle obl = true) ->
    (forall obl, T.GeneratedCoherency obl -> Oref.Oracle obl = true) ->
    (forall obl, T.GeneratedObjective obl -> Oalt.Oracle obl = Oref.Oracle obl) ->
    (forall obl, T.GeneratedCoherency obl -> Oalt.Oracle obl = Oref.Oracle obl) ->
    forall u,
      Cov.AvoidA u ->
      Cov.AvoidG (C.run_trace u)
      /\
      (forall k (obl : E.Obligation),
         T.GeneratedCoherency obl ->
         obl (C.ctx_at u k)).
  Proof.
    intros HallRefObj HallRefCoh HagreeObj HagreeCoh u HA.
    apply ObjAlt.oracle_conditional_correctness_with_coherency.
    - intros obl Hobj.
      rewrite HagreeObj; [|exact Hobj].
      apply HallRefObj.
      exact Hobj.
    - intros obl Hcoh.
      rewrite HagreeCoh; [|exact Hcoh].
      apply HallRefCoh.
      exact Hcoh.
    - exact HA.
  Qed.
End MakeSupportNonBlockingKernel.
