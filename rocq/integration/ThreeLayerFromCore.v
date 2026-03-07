From Stdlib Require Import Logic.Classical.

Require Import integration.ThreeLayerArchitecture.

Set Implicit Arguments.

(*
  Alternative core-layer interface: instead of postulating
  [coverage_if_not_avoidG] directly, it is reconstructed from two
  proved ingredients (global violation -> local bad step, and local bad
  step -> generated violated obligation).
*)
Module Type KAIROS_CORE_FROM_PROVED_SIG (P : PROGRAM_LAYER_SIG).
  Include obligations.ObligationGenSig.OBLIGATION_GEN_SIG
    with Definition StepCtx := P.StepCtx.

  Parameter bad_local_step : (nat -> P.InputVal) -> nat -> Prop.

  Parameter bad_local_step_if_G_violated :
    forall (u : nat -> P.InputVal),
      P.AvoidA u ->
      ~ P.AvoidG (P.run_trace u) ->
      exists k, bad_local_step u k.

  Parameter generation_coverage_from_bad_local_step :
    forall (u : nat -> P.InputVal) (k : nat),
      bad_local_step u k ->
      exists cl : Clause,
        Generated cl /\ ~ cl (P.ctx_at u k).
End KAIROS_CORE_FROM_PROVED_SIG.

Module MakeCoverageFromProvedCore
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P).

  Theorem coverage_if_not_avoidG :
    forall u,
      P.AvoidA u ->
      ~ P.AvoidG (P.run_trace u) ->
      exists k (cl : K.Clause),
        K.Generated cl /\ ~ cl (P.ctx_at u k).
  Proof.
    intros u HA HnG.
    destruct (K.bad_local_step_if_G_violated (u := u) HA HnG) as [k Hbad].
    destruct (K.generation_coverage_from_bad_local_step (u := u) (k := k) Hbad)
      as [cl [Hgen Hnot]].
    exists k, cl.
    split; assumption.
  Qed.
End MakeCoverageFromProvedCore.
