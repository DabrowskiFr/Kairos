From SpecV2 Require Import
  ReactiveModel ConditionalSafety ExplicitProduct GeneratedClauses RelationalTriples Soundness.

Set Implicit Arguments.

(** * Relative Completeness

    This module proves the converse admissible-run results stated in the paper.
    They are relative because they only speak about admissible runs and because
    invariant-related triples additionally rely on the semantic truth of the
    user invariants. *)

Section RelativeCompleteness.
  Context (P : ReactiveProgram).
  Context (Spec : ConditionalSpec P).
  Variable node_inv : ProgState P -> @TickCtx P Spec -> Prop.

  (** Global conditional correctness. *)
  Definition globally_correct : Prop :=
    forall u,
      AvoidA Spec u ->
      AvoidG Spec u.

  (** Truth of the user invariant family on admissible runs. *)
  Definition node_invariants_on_runs : Prop :=
    forall m0 u k,
      AvoidA Spec u ->
      node_inv (state_from P m0 u k) (@ctx_from P Spec m0 u k).

  (** A coherent abstract state is uniquely determined by the current concrete
      run context. *)
  Local Lemma coherence_now_exact :
    forall m0 u k st,
      coherence_now st (@ctx_from P Spec m0 u k) ->
      st = @product_state_from P Spec m0 u k.
  Proof.
    intros m0 u k [sp sa sg] [Hs [Ha Hg]].
    simpl in *.
    subst; reflexivity.
  Qed.

  (** Matching plus coherence determine the next concrete product state of a
      well-formed step. *)
  Local Lemma target_is_next_state :
    forall m0 u k ps,
      product_step_wf ps ->
      ctx_matches_ps (@ctx_from P Spec m0 u k) ps ->
      coherence_now (pst_from ps) (@ctx_from P Spec m0 u k) ->
      pst_target ps = @product_state_from P Spec m0 u (S k).
  Proof.
    intros m0 u k [src t m i o tgt] Hwf Hmatch Hcoh.
    simpl in *.
    destruct src as [sp sa sg].
    simpl in *.
    destruct Hmatch as [Hs [Hm [Hi [Ho Ht]]]].
    destruct Hcoh as [Hsp [Hsa Hsg]].
    simpl in Hs, Hm, Hi, Ho, Ht, Hsp, Hsa, Hsg.
    subst.
    unfold product_step_wf in Hwf.
    simpl in Hwf.
    rewrite Hwf.
    unfold product_step_target_of.
    simpl.
    unfold product_state_from, state_from, trans_from,
      assume_state_at, guarantee_state_at, trace_from.
    rewrite cfg_from_S.
    remember (cfg_from P m0 u k) as cfg eqn:Hcfg.
    destruct cfg as [s mcur].
    simpl.
    reflexivity.
  Qed.

  (** First relative-completeness result: global correctness validates all
      generated [NoBad] triples on admissible runs. *)
  Theorem relative_completeness_no_bad :
    globally_correct ->
    forall ps,
      product_step_wf ps ->
      product_step_is_bad_target ps ->
      @TripleValidOnAdmissibleRuns P Spec (no_bad_triple node_inv ps).
  Proof.
    intros Hglob ps Hwf Hbad.
    simpl.
    intros m0 u k HA Ht [Hmatch [Hinv Hcoh]].
    pose proof
      (target_is_next_state
         (m0 := m0) (u := u) (k := k) (ps := ps) Hwf Hmatch Hcoh)
      as Htgt.
    destruct Hbad as [Hgbad _].
    rewrite Htgt in Hgbad.
    assert (~ avoids_bad (guarantee_aut Spec) (trace_from P m0 u)).
    { intro Havoid.
      specialize (Havoid (S k)).
      exact (Havoid Hgbad). }
    exfalso.
    apply H.
    specialize (Hglob u HA m0).
    exact Hglob.
  Qed.

  (** Automaton-coherence propagation triples are also semantically justified on
      admissible runs by global correctness. *)
  Theorem relative_completeness_automaton_coherence :
    @TripleValidOnAdmissibleRuns P Spec (@init_coherence_triple P Spec)
    /\
    forall ps,
      product_step_wf ps ->
      @TripleValidOnAdmissibleRuns P Spec (coherence_triple ps).
  Proof.
    split.
    - simpl.
      intros m0 u _ _.
      repeat split; reflexivity.
    - intros ps Hwf.
      simpl.
      intros m0 u k _ _ [Hmatch Hcoh].
      unfold automaton_coherence_clause.
      change (coherence_now (pst_target ps) (@ctx_from P Spec m0 u (S k))).
      rewrite (target_is_next_state
                 (m0 := m0) (u := u) (k := k) (ps := ps) Hwf Hmatch Hcoh).
      apply (@coherence_now_from_run P Spec m0 u (S k)).
  Qed.

  (** User-invariant triples require the additional semantic hypothesis that the
      invariant family is actually true on admissible runs. *)
  Theorem relative_completeness_user_invariant :
    node_invariants_on_runs ->
    @TripleValidOnAdmissibleRuns P Spec (@init_node_inv_triple P Spec node_inv)
    /\
    forall ps,
      product_step_wf ps ->
      @TripleValidOnAdmissibleRuns P Spec (node_inv_triple node_inv ps).
  Proof.
    intros Htrue.
    split.
    - simpl.
      intros m0 u HA _.
      exact (Htrue m0 u 0 HA).
    - intros ps Hwf.
      simpl.
      intros m0 u k HA _ [Hmatch [Hinv Hcoh]].
      change (node_inv (ps_prog (pst_target ps)) (@ctx_from P Spec m0 u (S k))).
      pose proof
        (target_is_next_state
           (m0 := m0) (u := u) (k := k) (ps := ps) Hwf Hmatch Hcoh) as Htgt.
      rewrite Htgt.
      exact (Htrue m0 u (S k) HA).
  Qed.

  (** Combined relative-completeness statement for all generated triples. *)
  Theorem relative_completeness_generated_triples :
    globally_correct ->
    node_invariants_on_runs ->
    forall ht,
      @GeneratedTriple P Spec node_inv ht ->
      @TripleValidOnAdmissibleRuns P Spec ht.
  Proof.
    intros Hglob Hnode ht [o Hgen].
    destruct Hgen.
    - destruct (relative_completeness_user_invariant Hnode) as [Hinit _].
      exact Hinit.
    - destruct relative_completeness_automaton_coherence as [Hinit _].
      exact Hinit.
    - destruct (relative_completeness_user_invariant Hnode) as [_ Hstep].
      apply Hstep; assumption.
    - destruct relative_completeness_automaton_coherence as [_ Hstep].
      apply Hstep; assumption.
    - eapply relative_completeness_no_bad; eauto.
  Qed.

End RelativeCompleteness.
