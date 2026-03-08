From Stdlib Require Import Classical.
From SpecV2 Require Import
  ReactiveModel ConditionalSafety ExplicitProduct GeneratedClauses RelationalTriples.

Set Implicit Arguments.

Section Soundness.
  Context (P : ReactiveProgram).
  Context (Spec : ConditionalSpec P).
  Variable node_inv : ProgState P -> @TickCtx P Spec -> Prop.

  Definition globally_correct : Prop :=
    forall u,
      AvoidA Spec u ->
      AvoidG Spec u.

  Hypothesis GeneratedTripleValid :
    forall ht : @RelHoareTriple P Spec,
      @GeneratedTriple P Spec node_inv ht ->
      @TripleValid P Spec ht.

  Hypothesis node_invariants_on_runs :
    forall m0 u k,
      AvoidA Spec u ->
      node_inv (state_from P m0 u k) (@ctx_from P Spec m0 u k).

  Local Lemma coherence_now_on_runs :
    forall m0 u k,
      coherence_now (@product_state_from P Spec m0 u k) (@ctx_from P Spec m0 u k).
  Proof.
    intros m0 u k.
    exact (@coherence_now_from_run P Spec m0 u k).
  Qed.

  Local Lemma current_tick_matches_step :
    forall m0 u k,
      ctx_matches_ps (@ctx_from P Spec m0 u k) (@selected_step_at P Spec m0 u k).
  Proof.
    intros m0 u k.
    exact (@selected_step_matches_ctx P Spec m0 u k).
  Qed.

  Local Lemma generated_no_bad_triple_contradiction :
    forall m0 u k,
      AvoidA Spec u ->
      product_step_is_bad_target (@selected_step_at P Spec m0 u k) ->
      False.
  Proof.
    intros m0 u k HA Hbad.
    pose proof
      (@GT_no_bad
         P Spec node_inv
         (@selected_step_at P Spec m0 u k)
         (@selected_step_at_wf P Spec m0 u k)
         Hbad) as Hgen.
    assert (Hgenerated :
      @GeneratedTriple P Spec node_inv
        (no_bad_triple node_inv (@selected_step_at P Spec m0 u k))).
    { exists OriginSafety; exact Hgen. }
    assert (Hvalid :
      @TripleValid P Spec
        (no_bad_triple node_inv (@selected_step_at P Spec m0 u k))).
    { apply GeneratedTripleValid. exact Hgenerated. }
    assert (Hvalid_run :
      @TripleValidOnAdmissibleRuns P Spec
        (no_bad_triple node_inv (@selected_step_at P Spec m0 u k))).
    { apply (@TripleValid_implies_TripleValidOnAdmissibleRuns P Spec). exact Hvalid. }
    simpl in Hvalid_run.
    specialize (Hvalid_run m0 u k HA eq_refl).
    apply Hvalid_run.
    split.
    - apply current_tick_matches_step.
    - split.
      + apply node_invariants_on_runs; assumption.
      + apply coherence_now_on_runs.
  Qed.

  Theorem validation_conditional_correctness :
    globally_correct.
  Proof.
    intros u HA m0.
    destruct (classic (avoids_bad (guarantee_aut Spec) (trace_from P m0 u))) as [HG|Hcontra].
    - exact HG.
    - destruct (@dangerous_step_of_global_violation P Spec m0 u HA Hcontra)
        as [k [_ [_ Hbad]]].
      exfalso.
      eapply generated_no_bad_triple_contradiction; eauto.
  Qed.
End Soundness.
