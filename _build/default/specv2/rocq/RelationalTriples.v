From SpecV2 Require Import ReactiveModel ConditionalSafety ExplicitProduct GeneratedClauses.

Set Implicit Arguments.

(** * Relational Hoare Triples

    This module packages the semantic clauses into local proof objects. The
    meaning of a triple remains semantic: validity quantifies over concrete tick
    contexts reconstructed from actual executions. *)

Section Triples.
  Context (P : ReactiveProgram).
  Context (Spec : ConditionalSpec P).
  Variable node_inv : ProgState P -> @TickCtx P Spec -> Prop.

  (** Alias used when clauses appear as preconditions or postconditions. *)
  Definition SemanticClause := @Clause P Spec.

  (** Triples are either attached to the initial tick or to one transition
      label. *)
  Inductive triple_target : Type :=
  | TripleInit
  | TripleStep (t : ProgTransition P).

  (** Relational Hoare triple generated from the reduction. Besides the target,
      precondition, and postcondition, it stores the origin and the generating
      clause it corresponds to. *)
  Record RelHoareTriple : Type := {
    ht_target : triple_target;
    ht_pre : SemanticClause;
    ht_post : SemanticClause;
    ht_origin : clause_origin;
    ht_clause : SemanticClause
  }.

  (** Initial tick contexts are exactly the contexts at time [0] on some run. *)
  Definition init_ctx (ctx : @TickCtx P Spec) : Prop :=
    exists m0 u,
      ctx = @ctx_from P Spec m0 u 0.

  (** [transition_rel t ctx ctx'] means that [ctx] and [ctx'] are successive
      concrete contexts linked by a tick selecting transition [t]. *)
  Definition transition_rel
      (t : ProgTransition P)
      (ctx ctx' : @TickCtx P Spec)
      : Prop :=
    exists m0 u k,
      ctx = @ctx_from P Spec m0 u k
      /\ ctx' = @ctx_from P Spec m0 u (S k)
      /\ trans_from P m0 u k = t.

  (** Full semantic validity of a triple. *)
  Definition TripleValid (ht : RelHoareTriple) : Prop :=
    match ht_target ht with
    | TripleInit =>
        forall ctx, init_ctx ctx -> ht_pre ht ctx -> ht_post ht ctx
    | TripleStep t =>
        forall ctx ctx', transition_rel t ctx ctx' -> ht_pre ht ctx -> ht_post ht ctx'
    end.

  (** Restricted validity on admissible runs only. *)
  Definition TripleValidOnAdmissibleRuns (ht : RelHoareTriple) : Prop :=
    match ht_target ht with
    | TripleInit =>
        forall m0 u,
          AvoidA Spec u ->
          ht_pre ht (@ctx_from P Spec m0 u 0) ->
          ht_post ht (@ctx_from P Spec m0 u 0)
    | TripleStep t =>
        forall m0 u k,
          AvoidA Spec u ->
          trans_from P m0 u k = t ->
          ht_pre ht (@ctx_from P Spec m0 u k) ->
          ht_post ht (@ctx_from P Spec m0 u (S k))
    end.

  (** Any fully valid triple is in particular valid on admissible runs. *)
  Lemma TripleValid_implies_TripleValidOnAdmissibleRuns :
    forall ht, TripleValid ht -> TripleValidOnAdmissibleRuns ht.
  Proof.
    intros [target pre post origin clause] Hvalid; simpl in *.
    destruct target as [|t].
    - intros m0 u _ Hpre.
      apply Hvalid.
      + exists m0, u; reflexivity.
      + exact Hpre.
    - intros m0 u k _ Ht Hpre.
      eapply Hvalid.
      + exists m0, u, k.
        repeat split; try assumption; reflexivity.
      + exact Hpre.
  Qed.

  (** Canonical always-true and always-false clauses used in the generated
      triple schemata. *)
  Definition TrueClause : SemanticClause := fun _ => True.
  Definition FalseClause : SemanticClause := fun _ => False.

  (** The remaining definitions implement the canonical triples of the
      reduction: initialization, propagation, and safety exclusion. *)
  Definition init_product_state : @ProductState P Spec :=
    {| ps_prog := init_state P;
       ps_assume := q0 (assume_aut Spec);
       ps_guarantee := q0 (guarantee_aut Spec) |}.

  Definition init_node_inv_triple : RelHoareTriple :=
    {| ht_target := TripleInit;
       ht_pre := TrueClause;
       ht_post := node_inv (init_state P);
       ht_origin := OriginInit CKNodeInvariant;
       ht_clause := node_inv_clause node_inv init_product_state |}.

  Definition init_coherence_triple : RelHoareTriple :=
    {| ht_target := TripleInit;
       ht_pre := TrueClause;
       ht_post := automaton_coherence_clause init_product_state;
       ht_origin := OriginInit CKAutomaton;
       ht_clause := automaton_coherence_clause init_product_state |}.

  Definition node_inv_triple (ps : @ProductStep P Spec) : RelHoareTriple :=
    {| ht_target := TripleStep (pst_trans ps);
       ht_pre := fun ctx =>
         ctx_matches_ps ctx ps
         /\ node_inv (ps_prog (pst_from ps)) ctx
         /\ coherence_now (pst_from ps) ctx;
       ht_post := node_inv (ps_prog (pst_target ps));
       ht_origin := OriginPropagation CKNodeInvariant;
       ht_clause := node_inv_clause node_inv (pst_target ps) |}.

  Definition coherence_triple (ps : @ProductStep P Spec) : RelHoareTriple :=
    {| ht_target := TripleStep (pst_trans ps);
       ht_pre := fun ctx =>
         ctx_matches_ps ctx ps /\ coherence_now (pst_from ps) ctx;
       ht_post := automaton_coherence_clause (pst_target ps);
       ht_origin := OriginPropagation CKAutomaton;
       ht_clause := automaton_coherence_clause (pst_target ps) |}.

  Definition no_bad_triple (ps : @ProductStep P Spec) : RelHoareTriple :=
    {| ht_target := TripleStep (pst_trans ps);
       ht_pre := fun ctx =>
         ctx_matches_ps ctx ps
         /\ node_inv (ps_prog (pst_from ps)) ctx
         /\ coherence_now (pst_from ps) ctx;
       ht_post := FalseClause;
       ht_origin := OriginSafety;
       ht_clause := no_bad_clause ps |}.

  Inductive GeneratedTripleBy : clause_origin -> RelHoareTriple -> Prop :=
  | GT_init_node_inv :
      GeneratedTripleBy (OriginInit CKNodeInvariant) init_node_inv_triple
  | GT_init_automaton :
      GeneratedTripleBy (OriginInit CKAutomaton) init_coherence_triple
  | GT_node_inv :
      forall ps,
        product_step_wf ps ->
        GeneratedTripleBy (OriginPropagation CKNodeInvariant) (node_inv_triple ps)
  | GT_automaton :
      forall ps,
        product_step_wf ps ->
        GeneratedTripleBy (OriginPropagation CKAutomaton) (coherence_triple ps)
  | GT_no_bad :
      forall ps,
        product_step_wf ps ->
        product_step_is_bad_target ps ->
        GeneratedTripleBy OriginSafety (no_bad_triple ps).

  Definition GeneratedTriple (ht : RelHoareTriple) : Prop :=
    exists o, GeneratedTripleBy o ht.
End Triples.
