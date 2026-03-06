Require Import DelayIntExample.
Require Import integration.ThreeLayerArchitecture.

Set Implicit Arguments.

Module DelayIntThreeLayerInstance.
Module KO := DelayIntProof.KO.

Definition m0 : DelayIntProof.Mem := 0.

Module Program <: PROGRAM_LAYER_SIG.
  Definition InputVal := DelayIntProof.Input.
  Definition OutputVal := DelayIntProof.Output.
  Definition Mem := DelayIntProof.Mem.
  Definition Ctrl := DelayIntProof.PState.
  Definition stream (A : Type) : Type := nat -> A.

  Definition StepCtx := KO.StepCtx InputVal OutputVal Mem Ctrl.
  Definition init_ctrl : Ctrl := DelayIntProof.SInit.
  Definition init_mem : Mem := m0.

  Definition step : Ctrl -> Mem -> InputVal -> Ctrl * Mem * OutputVal :=
    fun c m i =>
      let r := KO.step DelayIntProof.paut DelayIntProof.pselect c m i in
      (KO.st_next r, KO.mem_next r, KO.out_cur r).

  Definition cfg_at : stream InputVal -> nat -> Ctrl * Mem :=
    KO.cfg_at DelayIntProof.paut DelayIntProof.pselect init_ctrl init_mem.

  Definition ctx_at : stream InputVal -> nat -> StepCtx :=
    KO.ctx_at DelayIntProof.paut DelayIntProof.pselect init_ctrl init_mem.

  Definition run_trace : stream InputVal -> stream (InputVal * OutputVal) :=
    KO.run_trace DelayIntProof.paut DelayIntProof.pselect init_ctrl init_mem.

  Definition cur_ctrl (ctx : StepCtx) : Ctrl := KO.cur_state ctx.
  Definition cur_mem (ctx : StepCtx) : Mem := KO.cur_mem ctx.
  Definition cur_input (ctx : StepCtx) : InputVal := KO.cur_input ctx.
  Definition cur_output (ctx : StepCtx) : OutputVal := KO.cur_output ctx.

  Lemma ctx_input_is_stream :
    forall u k, cur_input (ctx_at u k) = u k.
  Proof.
    intros u k.
    unfold cur_input, ctx_at, KO.ctx_at.
    destruct (KO.cfg_at DelayIntProof.paut DelayIntProof.pselect init_ctrl init_mem u k) as [c m].
    reflexivity.
  Qed.

  Lemma cfg_ctx_coherent :
    forall u k, (cur_ctrl (ctx_at u k), cur_mem (ctx_at u k)) = cfg_at u k.
  Proof.
    intros u k.
    unfold cur_ctrl, cur_mem, ctx_at, cfg_at, KO.ctx_at.
    destruct (KO.cfg_at DelayIntProof.paut DelayIntProof.pselect init_ctrl init_mem u k) as [c m].
    reflexivity.
  Qed.

  Lemma trace_ctx_coherent :
    forall u k, run_trace u k = (cur_input (ctx_at u k), cur_output (ctx_at u k)).
  Proof.
    intros u k.
    unfold run_trace, KO.run_trace.
    unfold cur_input, cur_output, ctx_at, KO.ctx_at.
    destruct (KO.cfg_at DelayIntProof.paut DelayIntProof.pselect init_ctrl init_mem u k) as [c m] eqn:Hcfg.
    simpl.
    unfold KO.out_at, KO.step_at, KO.step.
    rewrite Hcfg.
    reflexivity.
  Qed.

  Definition AvoidA (u : nat -> InputVal) : Prop :=
    KO.avoids_bad_A DelayIntProof.A_aut_e DelayIntProof.select_A u.

  Definition AvoidG (w : nat -> (InputVal * OutputVal)) : Prop :=
    KO.avoids_bad_G DelayIntProof.G_aut_e DelayIntProof.select_G w.

  Lemma avoidA_all : forall u, AvoidA u.
  Proof.
    intro u.
    exact (DelayIntProof.avoids_bad_A_delay u).
  Qed.

  Lemma avoidG_run_trace_all : forall u, AvoidG (run_trace u).
  Proof.
    intro u.
    exact (DelayIntProof.avoids_bad_G_delay m0 u).
  Qed.
End Program.

Module Core <: KAIROS_CORE_LAYER_SIG Program.
  Definition StepCtx := Program.StepCtx.
  Definition Obligation : Type := StepCtx -> Prop.
  Definition Origin := unit.
  Definition GeneratedBy (_ : Origin) (_ : Obligation) : Prop := False.
  Definition Generated (obl : Obligation) : Prop :=
    exists o, GeneratedBy o obl.

  Lemma coverage_if_not_avoidG :
    forall u,
      Program.AvoidA u ->
      ~ Program.AvoidG (Program.run_trace u) ->
      exists k (obl : Obligation), Generated obl /\ ~ obl (Program.ctx_at u k).
  Proof.
    intros u _HA HnG.
    exfalso.
    apply HnG.
    apply Program.avoidG_run_trace_all.
  Qed.
End Core.

Module Validation <: VALIDATION_LAYER_SIG Program Core.
  Definition Oracle (_ : Core.Obligation) : bool := false.
  Definition ObligationValid (obl : Core.Obligation) : Prop :=
    forall u k, obl (Program.ctx_at u k).

  Lemma Oracle_sound :
    forall obl, Oracle obl = true -> ObligationValid obl.
  Proof.
    intros obl H.
    discriminate H.
  Qed.

  Lemma Oracle_complete :
    forall obl, Core.Generated obl -> Oracle obl = true.
  Proof.
    intros obl [o Hgen].
    contradiction.
  Qed.

  Lemma obligation_valid_pointwise :
    forall (obl : Core.Obligation) u k,
      ObligationValid obl ->
      obl (Program.ctx_at u k).
  Proof.
    intros obl u k Hvalid.
    exact (Hvalid u k).
  Qed.
End Validation.

Module Correctness := MakeThreeLayerCorrectness Program Core Validation.

Theorem delay_int_three_layer_correctness :
  forall u,
    Program.AvoidA u ->
    Program.AvoidG (Program.run_trace u).
Proof.
  apply Correctness.oracle_conditional_correctness_three_layers.
Qed.

Theorem delay_int_three_layer_unconditional :
  forall u,
    Program.AvoidG (Program.run_trace u).
Proof.
  intro u.
  apply delay_int_three_layer_correctness.
  apply Program.avoidA_all.
Qed.

End DelayIntThreeLayerInstance.
