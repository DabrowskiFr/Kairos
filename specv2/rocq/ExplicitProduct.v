From Stdlib Require Import Arith Lia.
From SpecV2 Require Import ReactiveModel ConditionalSafety.

Set Implicit Arguments.

(** * Explicit Product

    This module is the semantic pivot of the reduction. It makes explicit the
    current program state together with the current assumption and guarantee
    automaton states. Once this product exists, global guarantee violations can
    be localized to dangerous product steps. *)

Section Product.
  Context (P : ReactiveProgram).
  Context (Spec : ConditionalSpec P).

  (** Product state combining the current program control state and both current
      automaton states. *)
  Record ProductState : Type := {
    ps_prog : ProgState P;
    ps_assume : AutState (assume_aut Spec);
    ps_guarantee : AutState (guarantee_aut Spec)
  }.

  (** Observable input/output letter emitted at tick [k]. *)
  Definition io_obs
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgInput P * ProgOutput P :=
    (u k, out_from P m0 u k).

  (** Product state reached on a concrete run after [k] ticks. *)
  Definition product_state_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProductState :=
    {|
      ps_prog := state_from P m0 u k;
      ps_assume := assume_state_at Spec u k;
      ps_guarantee := guarantee_state_at Spec m0 u k
    |}.

  (** Fully explicit one-tick semantic object. *)
  Record ProductStep : Type := {
    pst_from : ProductState;
    pst_trans : ProgTransition P;
    pst_mem : ProgMem P;
    pst_input : ProgInput P;
    pst_output : ProgOutput P;
    pst_target : ProductState
  }.

  (** Canonical target induced by one source product state and the local data of
      a tick. *)
  Definition product_step_target_of
      (src : ProductState)
      (t : ProgTransition P)
      (m : ProgMem P)
      (i : ProgInput P)
      (o : ProgOutput P)
      : ProductState :=
    {|
      ps_prog := dst_state P t (ps_prog src);
      ps_assume := qstep (assume_aut Spec) (ps_assume src) i;
      ps_guarantee := qstep (guarantee_aut Spec) (ps_guarantee src) (i, o)
    |}.

  (** Reification of the concrete step taken at time [k] along a run. *)
  Definition selected_step_at
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProductStep :=
    let src := product_state_from m0 u k in
    let m := mem_from P m0 u k in
    let i := u k in
    let t := trans_from P m0 u k in
    let o := out_from P m0 u k in
    {|
      pst_from := src;
      pst_trans := t;
      pst_mem := m;
      pst_input := i;
      pst_output := o;
      pst_target := product_step_target_of src t m i o
    |}.

  (** Structural well-formedness of a product step: the stored target must match
      the target computed from the source and the local semantic data. *)
  Definition product_step_wf (ps : ProductStep) : Prop :=
    pst_target ps =
    product_step_target_of
      (pst_from ps)
      (pst_trans ps)
      (pst_mem ps)
      (pst_input ps)
      (pst_output ps).

  Definition product_step_realized_at
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      (ps : ProductStep)
      : Prop :=
    ps = selected_step_at m0 u k.

  (** Dangerous product step: the guarantee moves to bad while the assumption
      remains non-bad. This is the local witness used by the reduction. *)
  Definition product_step_is_bad_target (ps : ProductStep) : Prop :=
    ps_guarantee (pst_target ps) = qbad (guarantee_aut Spec)
    /\ ps_assume (pst_target ps) <> qbad (assume_aut Spec).

  Record TickCtx : Type := {
    tick : nat;
    cur_state : ProgState P;
    cur_mem : ProgMem P;
    cur_input : ProgInput P;
    cur_output : ProgOutput P;
    cur_trans : ProgTransition P;
    cur_assume : AutState (assume_aut Spec);
    cur_guarantee : AutState (guarantee_aut Spec);
    next_state : ProgState P;
    next_mem : ProgMem P;
    next_assume : AutState (assume_aut Spec);
    next_guarantee : AutState (guarantee_aut Spec)
  }.

  Definition ctx_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : TickCtx :=
    let src := product_state_from m0 u k in
    let tgt := product_state_from m0 u (S k) in
    {|
      tick := k;
      cur_state := ps_prog src;
      cur_mem := mem_from P m0 u k;
      cur_input := u k;
      cur_output := out_from P m0 u k;
      cur_trans := trans_from P m0 u k;
      cur_assume := ps_assume src;
      cur_guarantee := ps_guarantee src;
      next_state := ps_prog tgt;
      next_mem := mem_from P m0 u (S k);
      next_assume := ps_assume tgt;
      next_guarantee := ps_guarantee tgt
    |}.

  (** The remaining lemmas connect the reified objects above to actual runs.
      They are the bridge used in soundness and completeness proofs. *)
  Lemma selected_step_at_wf :
    forall m0 u k, product_step_wf (selected_step_at m0 u k).
  Proof.
    intros; unfold product_step_wf, selected_step_at; simpl; reflexivity.
  Qed.

  Proposition selected_step_exists :
    forall m0 u k,
      exists ps,
        product_step_wf ps /\ product_step_realized_at m0 u k ps.
  Proof.
    intros m0 u k.
    exists (selected_step_at m0 u k).
    split.
    - apply selected_step_at_wf.
    - reflexivity.
  Qed.

  Proposition coherence_now_from_run :
    forall m0 u k,
      let st := product_state_from m0 u k in
      cur_state (ctx_from m0 u k) = ps_prog st
      /\ cur_assume (ctx_from m0 u k) = ps_assume st
      /\ cur_guarantee (ctx_from m0 u k) = ps_guarantee st.
  Proof.
    intros m0 u k st; simpl; auto.
  Qed.

  Proposition coherence_next_on_run :
    forall m0 u k,
      let st := product_state_from m0 u (S k) in
      next_state (ctx_from m0 u k) = ps_prog st
      /\ next_assume (ctx_from m0 u k) = ps_assume st
      /\ next_guarantee (ctx_from m0 u k) = ps_guarantee st.
  Proof.
    intros m0 u k st; simpl; auto.
  Qed.

  Lemma selected_step_matches_ctx :
    forall m0 u k,
      let ps := selected_step_at m0 u k in
      cur_state (ctx_from m0 u k) = ps_prog (pst_from ps)
      /\ cur_mem (ctx_from m0 u k) = pst_mem ps
      /\ cur_input (ctx_from m0 u k) = pst_input ps
      /\ cur_output (ctx_from m0 u k) = pst_output ps
      /\ cur_trans (ctx_from m0 u k) = pst_trans ps.
  Proof.
    intros m0 u k ps.
    unfold ps, selected_step_at; simpl; repeat split.
  Qed.

  Proposition dangerous_step_of_global_violation :
    forall (m0 : ProgMem P) (u : stream (ProgInput P)),
      AvoidA Spec u ->
      ~ avoids_bad (guarantee_aut Spec) (trace_from P m0 u) ->
      exists k,
        product_step_realized_at m0 u k (selected_step_at m0 u k)
        /\ product_step_wf (selected_step_at m0 u k)
        /\ product_step_is_bad_target (selected_step_at m0 u k).
  Proof.
    intros m0 u HA HG.
    destruct (@bad_successor_of_not_avoidG P Spec m0 u HG) as [k Hk].
    exists k.
    split.
    - reflexivity.
    - split.
      + apply selected_step_at_wf.
      + unfold product_step_is_bad_target, selected_step_at.
        unfold guarantee_state_at in Hk.
        simpl in Hk.
        simpl.
        split.
        * change
            (qstep
               (guarantee_aut Spec)
               (run_aut (guarantee_aut Spec) (@trace_from P m0 u) k)
               (u k, out_from P m0 u k) =
             qbad (guarantee_aut Spec)).
          exact Hk.
        * apply (HA (S k)).
  Qed.
End Product.
