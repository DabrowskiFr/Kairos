From Stdlib Require Import Logic.Classical.

Require Import core.CoreStepSig.
Require Import core.CoreReactiveLaws.
Require Import obligations.ObligationGenSig.
Require Import obligations.OracleSig.
Require Import obligations.OracleSemSig.

Set Implicit Arguments.

Module Type PROGRAM_LAYER_SIG.
  Include CORE_STEP_SIG.

  Parameter cur_ctrl : StepCtx -> Ctrl.
  Parameter cur_mem : StepCtx -> Mem.
  Parameter cur_input : StepCtx -> InputVal.
  Parameter cur_output : StepCtx -> OutputVal.

  Axiom ctx_input_is_stream :
    forall u k, cur_input (ctx_at u k) = u k.

  Axiom cfg_ctx_coherent :
    forall u k, (cur_ctrl (ctx_at u k), cur_mem (ctx_at u k)) = cfg_at u k.

  Axiom trace_ctx_coherent :
    forall u k, run_trace u k = (cur_input (ctx_at u k), cur_output (ctx_at u k)).

  Parameter AvoidA : (nat -> InputVal) -> Prop.
  Parameter AvoidG : (nat -> (InputVal * OutputVal)) -> Prop.
End PROGRAM_LAYER_SIG.

Module Type KAIROS_CORE_LAYER_SIG (P : PROGRAM_LAYER_SIG).
  Include OBLIGATION_GEN_SIG with Definition StepCtx := P.StepCtx.

  Axiom coverage_if_not_avoidG :
    forall u,
      P.AvoidA u ->
      ~ P.AvoidG (P.run_trace u) ->
      exists k (cl : Clause), Generated cl /\ ~ cl (P.ctx_at u k).
End KAIROS_CORE_LAYER_SIG.

Module Type VALIDATION_LAYER_SIG
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_LAYER_SIG P).
  Include ORACLE_SEM_SIG P K.
End VALIDATION_LAYER_SIG.

Module MakeThreeLayerCorrectness
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_LAYER_SIG P)
  (S : VALIDATION_LAYER_SIG P K).

  Theorem validation_conditional_correctness_three_layers :
    forall u,
      P.AvoidA u ->
      P.AvoidG (P.run_trace u).
  Proof.
    intros u HA.
    destruct (classic (P.AvoidG (P.run_trace u))) as [HG | HnG].
    - exact HG.
    - destruct (@K.coverage_if_not_avoidG u HA HnG) as [k [cl [Hgen Hnot]]].
      pose proof (S.Oracle_complete (cl := cl) Hgen) as Hor.
      pose proof (S.Oracle_sound (cl := cl) Hor) as Hvalid.
      exfalso.
      apply Hnot.
      exact (S.clause_valid_pointwise u k Hvalid).
  Qed.

  Theorem oracle_conditional_correctness_three_layers :
    forall u,
      P.AvoidA u ->
      P.AvoidG (P.run_trace u).
  Proof.
    exact validation_conditional_correctness_three_layers.
  Qed.
End MakeThreeLayerCorrectness.
